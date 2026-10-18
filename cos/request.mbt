///|
/// 发一次已签名的请求，并把非 2xx 翻成 `CosError::Service`。
///
/// 三处与隔壁 `moon-oss` 反着来，逐条写在代码旁边而不是文档里：
/// · `Host` **要进签**（三份参照实现默认都签），但**不上请求头**——传输层按 URL 自己写
///   那一行，我们签的是同一个串。OSS 那边正相反：把 host 算进头块当场 `SignatureDoesNotMatch`。
/// · 签名串里是**解码态**的 path 与**小写＋编码后**的参数键；发出去的查询串保留原样键名
///   （`partNumber`／`uploadId` 是驼峰）与编码后的值。两处不同形是本家协议的定义，不是 bug。
/// · 空值参数在签名里写 `acl=`（带等号），请求行里也写 `acl=`。OSS V4 是无值只写键名。
async fn request(
  client : Client,
  verb : String,
  bucket~ : String = "",
  key~ : String = "",
  query~ : Array[(String, String)] = [],
  headers~ : Array[(String, String)] = [],
  body~ : @transport.RequestBody = @transport.RequestBody::Empty,
) -> @transport.Response raise @error.CosError {
  let config = client.config
  let host = if bucket.is_empty() {
    service_host()
  } else {
    config.host(bucket)
  }
  let path = @config.path_of(key)
  let signed = [("host", host)] + headers
  let window = @auth.window_at(@auth.now_millis(), 3600L)
  let authorization = @auth.authorization(
    config.credentials(),
    @auth.RequestToSign::{ verb, path, query, headers: signed, },
    window,
  )
  let url = "https://" + host + "/" + @config.encode_key(key)
  let wire_query = wire_query(query)
  let full_url = if wire_query.is_empty() {
    url
  } else {
    url + "?" + wire_query
  }
  let wire : Array[@transport.Header] = []
  for pair in headers {
    wire.push(@transport.Header::{ name: pair.0, value: pair.1, })
  }
  wire.push(@transport.Header::{ name: "authorization", value: authorization, })
  let http_method = method_of(verb)
  let response = client.transport.send(@transport.Request::{
    http_method,
    url: full_url,
    headers: wire,
    body,
  }) catch {
    err => raise @error.Network(transport_text(err))
  }
  if response.status >= 200 && response.status < 300 {
    response
  } else {
    let body_stream = response.body
    let text = response_body_text(body_stream, response.status)
    raise @error.Service(@error.ServiceError::{
      status: response.status,
      code: xml_error_code(text),
      message: or_empty(xml_first(text, "Message")),
      request_id: header_of(response.headers, "x-cos-request-id"),
      trace_id: or_empty(xml_first(text, "TraceId")),
    })
  }
}

///|
/// 服务级列举桶走的是这一个域，不是某个桶的域（参照实现同形）。
fn service_host() -> String {
  "service.cos.myqcloud.com"
}

///|
/// 发出去的查询串：键按原样（驼峰保留），值编码；空值渲染成 `k=`。
fn wire_query(query : Array[(String, String)]) -> String {
  let parts : Array[String] = []
  for pair in query {
    parts.push(@auth.cos_encode(pair.0) + "=" + @auth.cos_encode(pair.1))
  }
  parts.join("&")
}

///|
fn method_of(verb : String) -> @transport.Method raise @error.CosError {
  match verb {
    "GET" => @transport.Method::Get
    "HEAD" => @transport.Method::Head
    "PUT" => @transport.Method::Put
    "POST" => @transport.Method::Post
    "DELETE" => @transport.Method::Delete
    _ => raise @error.BadParam("unsupported verb: " + verb)
  }
}

///|
/// 问号之后一律隐去。传输层的文案有几档会把整条 URL 原样写进去（hutool 的
/// `InvalidRequest`：`url 缺 :// 分隔`、`url 带 fragment`、`url 缺 authority`、`pathless query`
/// 四档都带），
/// 而预签名 URL 的 query **就是凭据本体**——`q-ak` 加一条时间窗内可用的签名，
/// 落进日志等于把这条授权又发出去一份。主机与路径留着：诊断要看的是"哪一发"，不是那把钥匙。
fn redact_query(text : String) -> String {
  match text.find("?") {
    None => text
    Some(at) => text[0:at].to_owned() + "?<redacted>"
  }
}

///|
fn transport_text(err : @transport.TransportError) -> String {
  match err {
    @transport.TransportError::Network(detail) =>
      "network: " + redact_query(detail)
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(detail) =>
      "invalid request: " + redact_query(detail)
    @transport.TransportError::InvalidResponse(detail) =>
      "invalid response: " + redact_query(detail)
  }
}

///|
fn or_empty(value : String?) -> String {
  match value {
    Some(v) => v
    None => ""
  }
}

///|
fn header_of(headers : Array[@transport.Header], name : String) -> String? {
  let want = name.to_lower()
  for h in headers {
    if h.name.to_lower() == want {
      return Some(h.value)
    }
  }
  None
}

///|
/// 把响应体读空。非 2xx 的分支也要读，否则除了状态码什么证据都没有。
async fn read_all(
  body : &@transport.ResponseBody,
) -> Bytes raise @error.CosError {
  let merged : Array[Byte] = []
  let mut reading = true
  while reading {
    let chunk = body.read(65536) catch {
      err => raise @error.Network(transport_text(err))
    }
    match chunk {
      Some(data) => merged.append(data.to_array())
      None => reading = false
    }
  }
  Bytes::from_array(merged)
}

///|
/// 本 SDK 全量读回的正文都按 UTF-8 解；解不开不是"网络断"也不是"服务端拒"，
/// 是这条应答本身没法用，所以单列 `BadResponse`，并把状态码带在文案里。
fn response_text(data : Bytes, status : Int32) -> String raise @error.CosError {
  @utf8.decode(data.exact_view()) catch {
    _ =>
      raise @error.BadResponse(
        "response body is not valid UTF-8, status " + status.to_string(),
      )
  }
}

///|
/// 读完并关掉响应体。**2xx 且不需要正文的那几条都必须走这一条**：
/// 传输层的池只收"读尽的线"，不读也不关等于把一条 TLS 连接晾在外面——
/// 隔壁 moon-oss 真桶实测过，晾着的连接会让后面的请求整等 30 秒再报 timeout。
async fn discard_body(
  response : @transport.Response,
) -> Unit raise @error.CosError {
  let body = response.body
  let _ = read_all(body)
  body.close()
}

///|
/// 成功分支的正文读数：调用方只要文本（列举、拷贝回执、分片完成回执）。
async fn response_body_text(
  body : &@transport.ResponseBody,
  status : Int32,
) -> String raise @error.CosError {
  let raw = read_all(body)
  body.close()
  response_text(raw, status)
}
