///|
/// 对象族：写、读、查、删、同平台复制。COS 的用户元数据只有 `x-cos-meta-*` 这一族，
/// 写进去与读回来用的是同一批头，所以这两侧的形状必须一起定。

///|
/// `metadata~` 里的键名**不带** `x-cos-meta-` 前缀：前缀是本协议的固定部分，
/// 让调用方重复写一遍只会多出"写了两次前缀"这一类错。
///
/// `acl~` 给的是原生词汇（`private`／`public-read`／`public-read-write`／`default`），
/// 本 SDK 不收 S3 那族的 `authenticated-read` 之类——参照实现自己列了七档，但对象预设
/// 那一档官方文档只给三个值加 `default`，多出来的档位没有实测根据就不承诺。
pub async fn Client::put_object(
  self : Client,
  bucket : String,
  key : String,
  data : Bytes,
  content_type~ : String = "",
  metadata~ : Array[(String, String)] = [],
  acl~ : CannedAcl = Private,
  set_acl~ : Bool = false,
) -> PutObjectResult raise @error.CosError {
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    headers=object_headers(
      content_type~,
      metadata~,
      acl~,
      set_acl~,
      copy_source="",
    ),
    body=@transport.RequestBody::Bytes(data),
  )
  discard_body(response)
  PutObjectResult::{ etag: or_empty(header_of(response.headers, "etag")), }
}

///|
/// 读对象。`range~` 给的是 HTTP Range 的原值（如 `bytes=0-3`），本 SDK 不翻译它——
/// 翻译一次就多一处与真端点理解不一致的地方。
pub async fn Client::get_object(
  self : Client,
  bucket : String,
  key : String,
  range~ : String = "",
) -> ObjectData raise @error.CosError {
  let extra : Array[(String, String)] = if range.is_empty() {
    []
  } else {
    [("range", range)]
  }
  let response = request(self, "GET", bucket~, key~, headers=extra)
  let body = read_all(response.body)
  response.body.close()
  ObjectData::{
    content_length: parse_int64(
      or_empty(header_of(response.headers, "content-length")),
    ),
    content_type: header_of(response.headers, "content-type"),
    metadata: meta_pairs(response.headers),
    content_range: header_of(response.headers, "content-range"),
    etag: header_of(response.headers, "etag"),
    body,
  }
}

///|
/// `HEAD /<key>`：只查不取。回 `NotFound` 档还是回 `Service` 档由调用方按状态码判——
/// 这一层不替业务决定"不存在"算不算错。
///
/// 真端点那一档（实测 M13）：COS 文档**没有**任何一句说 HEAD 的 404 带不带正文，
/// 参照实现的 `IsExist` 也是"状态码＋Code 双看、不假设有 body"。所以判"不存在"
/// 只看 `status`，`code` 可能是空串。
pub async fn Client::stat_object(
  self : Client,
  bucket : String,
  key : String,
) -> ObjectStat raise @error.CosError {
  let response = request(self, "HEAD", bucket~, key~)
  discard_body(response)
  ObjectStat::{
    key,
    etag: header_of(response.headers, "etag"),
    size: parse_int64(or_empty(header_of(response.headers, "content-length"))),
    last_modified: header_of(response.headers, "last-modified"),
    content_type: header_of(response.headers, "content-type"),
    metadata: meta_pairs(response.headers),
  }
}

///|
pub async fn Client::delete_object(
  self : Client,
  bucket : String,
  key : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, key~)
  discard_body(response)
}

///|
/// 同平台复制。头名是 `x-cos-copy-source`，值是**一整个源站主机名加编码后的键**
/// （`<源桶>.cos.<region>.myqcloud.com/<key>`），不是 S3 那族的 `/<源桶>/<源键>`——
/// 这一处形状差抄错就是 404／`InvalidArgument`，不是签名错，所以真桶那一发必须实测。
pub async fn Client::copy_object(
  self : Client,
  source_bucket : String,
  source_key : String,
  bucket : String,
  key : String,
  metadata~ : Array[(String, String)] = [],
) -> CopyResult raise @error.CosError {
  let source = self.config.host(source_bucket) +
    "/" +
    @config.encode_key(source_key)
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    headers=object_headers(metadata~, copy_source=source),
  )
  let body = response_body_text(response.body, response.status)
  CopyResult::{ etag: or_empty(xml_first(body, "ETag")), body, }
}

///|
/// 组装对象族那一族请求头。`x-cos-acl` 与 `x-cos-copy-source` 都是 `x-cos-*`，
/// 靠前缀自动入签；`content-type` 在白名单里。空值的头**不进数组**——参照实现的头块
/// 会跳过空值行，我们多发一行 `x-cos-meta-:` 就会与它算出的规范化串差一行。
///
/// `set_acl~=false` 时**根本不发** `x-cos-acl`：对象默认是 `default`（继承桶权限），
/// 而参照实现对"没指定 ACL"这件事的姿势是不发头，多发一行就改签名、也改服务端行为。
fn object_headers(
  content_type~ : String = "",
  metadata~ : Array[(String, String)] = [],
  acl~ : CannedAcl = Private,
  set_acl~ : Bool = false,
  copy_source~ : String = "",
) -> Array[(String, String)] {
  let headers : Array[(String, String)] = []
  if !content_type.is_empty() {
    headers.push(("content-type", content_type))
  }
  if set_acl {
    headers.push(("x-cos-acl", acl.text()))
  }
  if !copy_source.is_empty() {
    headers.push(("x-cos-copy-source", copy_source))
  }
  for pair in metadata {
    headers.push(("x-cos-meta-" + pair.0, pair.1))
  }
  headers
}

///|
/// 把响应头里的 `x-cos-meta-*` 收回来并去掉前缀，与 `metadata~` 入参同一坐标系。
fn meta_pairs(headers : Array[@transport.Header]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let prefix = "x-cos-meta-"
  for h in headers {
    let name = h.name.to_lower()
    if name.has_prefix(prefix) {
      out.push((name[prefix.length():name.length()].to_owned(), h.value))
    }
  }
  out
}
