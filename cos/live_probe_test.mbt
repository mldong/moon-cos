///|
// 只有真端点能裁决的那几档：要发的形态**不在**公开面上（`sha256` 参照实现根本没有、
// `list-type=2` 原生文档没有），所以它们不配进 SDK 的 API，只配在这里留读数。
// 走的是"自己拼一条签名请求"的路子，公开面一个字都不为它们长大。
//
// Env 与 live_test.mbt 同一批（这两个文件同属一个测试包，helper 只在那边定义一次）。
//
// 每一档都写成"两臂都断得住"的形状：接受就断接受的后果，拒就断拒绝的码，
// 落在两臂之外（5xx、传输错、别的码）一律当场红。读数全部 println 出来，便于逐条核对。

///|
/// 测试侧的查询串拼装：与 SDK 那侧同规则（键按原样、值编码、空值写 `k=`）。
/// 这几档的键全是 ASCII，签名里的"小写编码后"形态与发出去的形态在这里逐字相同，
/// 所以一条 URL 可以同时喂两处——这一点也写在每档的注释里。
fn probe_wire(query : Array[(String, String)]) -> String {
  let parts : Array[String] = []
  for pair in query {
    parts.push(@auth.cos_encode(pair.0) + "=" + @auth.cos_encode(pair.1))
  }
  parts.join("&")
}

///|
async fn probe_get(
  host : String,
  path : String,
  query : Array[(String, String)],
  authorization : String,
) -> (Int32, String) {
  let q = probe_wire(query)
  let url = if q.is_empty() {
    "https://" + host + path
  } else {
    "https://" + host + path + "?" + q
  }
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  let response = transport.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url,
    headers: [
      @transport.Header::{ name: "authorization", value: authorization, },
    ],
    body: @transport.RequestBody::Empty,
  }) catch {
    err => fail("probe request raised " + transport_text(err))
  }
  let status = response.status
  let body = drain(response.body)
  (status, @utf8.decode_lossy(body.exact_view()))
}

///|
/// M1：`q-sign-algorithm=sha256` 真端点收不收。三份官方 SDK 全把这个字段写死成 `sha1`
/// （Go 的 `switch` 只有 sha1 一个 case、default 也回落 sha1；Python 的签名模板字面就是
/// `q-sign-algorithm=sha1`），sha256 只在"兼容 AWS S3"的语境里出现过。
/// 这一发用 **HMAC-SHA256 两次＋SHA-256 摘要** 现签一条桶根 GET。
/// **测出来收也不写进承诺面**：没有参照实现的行为不实现（实测这一档就是 403）。
async fn probe_sha256(host : String, ak : String, sk : String) -> String {
  let key_time = "1000000000;1000099999"
  // 桶根 GET：参数段为空、头段只有 host。这一串规范化结果没有任何需要编码的字符，
  // 手写与 canonicalize 走的是同一条路，所以这里不需要借 SDK 的内部件。
  let info = "get\n/\n\nhost=" + host + "\n"
  let to_sign = "sha256\n" + key_time + "\n" + @digest.sha256_hex(info) + "\n"
  let derived = @digest.hmac_sha256_hex(sk, key_time)
  let digest = @digest.hmac_sha256_hex(derived, to_sign)
  let authorization = "q-sign-algorithm=sha256&q-ak=" +
    ak +
    "&q-sign-time=" +
    key_time +
    "&q-key-time=" +
    key_time +
    "&q-header-list=host&q-url-param-list=&q-signature=" +
    digest
  let (status, _) = probe_get(host, "/", [], authorization)
  status.to_string()
}

///|
async test "M1：sha256 那一档的端点读数（收下或拒下，落在两臂之外就红）" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let host = @config.Config::new(
        region(),
        @auth.Credentials::new(environment.0, environment.1),
      ).host(bucket())
      let reading = probe_sha256(host, environment.0, environment.1)
      println("M1 读数：q-sign-algorithm=sha256 → " + reading)
      assert_true(reading == "200" || reading.has_prefix("403"))
    }
  }
}

///|
/// M7：原生数据面吃不吃 `?list-type=2`。文档的参数表里没有它，三份参照实现全文搜不到
/// `list-type`——预期是"被忽略、仍回 V1 形态"。但"被忽略"与"被拒"是两件事：后者会让
/// 带 V2 参数的调用整条红，所以这一档要读数，不要预期。
async test "M7：原生列举带 list-type=2 时到底回什么形态" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let b = bucket()
      let root = prefix("m7")
      let config = client.config
      let _ = client.put_object(b, root + "/a.txt", @utf8.encode("m7"))
      let query = [
        ("list-type", "2"),
        ("prefix", root),
        ("encoding-type", "url"),
      ]
      let window = @auth.window_at(@auth.now_millis(), 3600L)
      let authorization = @auth.authorization(
        config.credentials(),
        @auth.RequestToSign::{
          verb: "get",
          path: "/",
          query,
          headers: [("host", config.host(b))],
        },
        window,
      )
      let (status, body) = probe_get(config.host(b), "/", query, authorization)
      let v2 = body.find("NextContinuationToken") is Some(_) ||
        body.find("<KeyCount>") is Some(_)
      let v1 = body.find("<Marker>") is Some(_)
      println(
        "M7 读数：status=" +
        status.to_string() +
        " 含 V2 成员=" +
        v2.to_string() +
        " 含 V1 Marker=" +
        v1.to_string(),
      )
      let _ = client.delete_object(b, root + "/a.txt")
      assert_no_residue(client, root)
      assert_eq(status, 200)
      // 收下但不换形态，就是"参数被忽略"；真回 V2 也认（那说明兼容层那条路能借道）
      assert_true(v1 || v2)
    }
  }
}

///|
/// M16：同名参数多值时服务端认不认"值也排序"那套规范化（只有 Go 那份真做，Python/JS
/// 用字典、多值互相覆盖）。我们的列举与分片都不发多值参数，所以这一档只记录、不承诺；
/// 将来要发多值的调用点必须先读这条读数。
async test "M16：多值同名参数送上去，签名认不认" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let config = client.config
      let b = bucket()
      let query = [
        ("prefix", "zzz"),
        ("prefix", "aaa"),
        ("encoding-type", "url"),
      ]
      let window = @auth.window_at(@auth.now_millis(), 3600L)
      let authorization = @auth.authorization(
        config.credentials(),
        @auth.RequestToSign::{
          verb: "get",
          path: "/",
          query,
          headers: [("host", config.host(b))],
        },
        window,
      )
      let (status, body) = probe_get(config.host(b), "/", query, authorization)
      println(
        "M16 读数：status=" +
        status.to_string() +
        " 正文里 Code=<" +
        (match xml_probe_code(body) {
          None => ""
          Some(code) => code
        }) +
        ">",
      )
      // 200＝多值被接受（签名按排序后的形态成立）；403＝服务端不认这套规范化。
      // 别的一律红：那说明这一发的形状我们没看懂。
      assert_true(status == 200 || status == 403)
    }
  }
}

///|
/// 只为本档读数用的最小取码：`<Code>` 的第一处。测试件里自己写一份，是为了不把
/// 内部解析件（`xml_first`）为了一条探针就抬成公开面。
fn xml_probe_code(body : String) -> String? {
  let open = "<Code>"
  let close = "</Code>"
  match body.find(open) {
    None => None
    Some(start) => {
      let from = start + open.length()
      let tail = body[from:body.length()].to_owned()
      match tail.find(close) {
        None => None
        Some(offset) => Some(body[from:from + offset].to_owned())
      }
    }
  }
}
