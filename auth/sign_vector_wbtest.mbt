///|
/// 签名件的向量档：期望值全部由一份**独立实现**算出（标准库 `hmac`/`hashlib` 写的 oracle，
/// 见阶段 H 卡 §4 最后一条给的工件目录），不是从本库的输出反抄的。
/// 每一档钉的是**整条 Authorization 串**——规范化、两个 list 的渲染、时间窗、签名四件事
/// 任何一处走偏都会当场红，比只断"签名等于"能多拦住"list 写空了但签名碰巧对"这一类。
///
/// 凭据是编出来的测试值，不是任何真密钥。

let vector_id = "AKIDtestid00000000000000000000"
let vector_key = "testSecretKey0123456789abcdef"
let vector_time = "1760000000;1760000600"
let vector_host = "mldong-test-1251150780.cos.ap-guangzhou.myqcloud.com"

///|
fn vector_window() -> Window {
  { start: 1760000000L, end: 1760000600L, }
}

///|
fn signed(
  verb : String,
  path : String,
  query : Array[(String, String)],
  headers : Array[(String, String)],
) -> String raise {
  let credentials = Credentials::new(vector_id, vector_key)
  authorization(
    credentials,
    RequestToSign::{ verb, path, query, headers, },
    vector_window(),
  )
}

///|
test "bucket-level GET on the root signs host only, with an empty parameter list" {
  let got = signed("GET", "/", [], [("host", vector_host)])
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=host&q-url-param-list=&q-signature=19b900477b96d0c48806eef74f294f2e5dff6162",
  )
}

///|
test "headers outside the signable list are dropped, the ones inside are sorted and encoded" {
  // `content-type` 的值 `text/plain` 编成 `text%2Fplain`；`x-cos-meta-*` 靠前缀进签
  let got = signed(
    "PUT",
    "/moonfs/notes.txt",
    [],
    [
      ("host", vector_host),
      ("Content-Type", "text/plain"),
      ("Content-Length", "11"),
      ("x-cos-meta-tool", "moon-cos"),
      ("Date", "ignored-by-the-scheme"),
      ("x-amz-anything", "not-a-cos-header"),
    ],
  )
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=content-length;content-type;host;x-cos-meta-tool" +
    "&q-url-param-list=&q-signature=78005a16cea1ff48799161bc56b2eda461cf608b",
  )
}

///|
test "a value-less sub-resource signs as `acl=`, with the equals sign kept" {
  // 这一档与 OSS V4 正相反：那边无值参数只写键名、不带 `=`。照 OSS 抄就红。
  let got = signed("GET", "/a.txt", [("acl", "")], [("host", vector_host)])
  assert_true(got.find("q-url-param-list=acl&q-signature=") is Some(_))
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=host&q-url-param-list=acl&q-signature=3ad6f0e226a2afa887fb7ab7664da97ed65a46ac",
  )
}

///|
test "parameter values are encoded, keys are lowercased, and the two do not have to agree" {
  // `partNumber`／`uploadId` 在签名里是小写键（参照实现先编码再整体小写），
  // 发出去的请求行仍是驼峰——这一档钉住"签的形态"与"发的形态"各自是什么。
  let got = signed(
    "PUT",
    "/big.bin",
    [("partNumber", "2"), ("uploadId", "78b501f4-dead-beef")],
    [("host", vector_host), ("Content-MD5", "kB1u3GRTa9rQIoM0MnV7YQ==")],
  )
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=content-md5;host&q-url-param-list=partnumber;uploadid" +
    "&q-signature=82a5bec5a3abf595f341f54a69b2daad291719d4",
  )
}

///|
test "a repeated parameter key appears once per value in the list, and values are sorted raw" {
  let got = signed(
    "GET",
    "/",
    [("tag", "b"), ("tag", "a"), ("tag", "c")],
    [("host", "example.cos.ap-guangzhou.myqcloud.com")],
  )
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=host&q-url-param-list=tag;tag;tag&q-signature=2a20e962c7128b4204855ca9293a9c6d87329ec6",
  )
}

///|
test "the path enters the signature raw: non-ASCII, space, plus, percent and ampersand all as given" {
  // 签名里是 `/中文 目录/+x%y&z.txt` 原样，一个百分号都没有——这是本家协议最反直觉的一条。
  // 请求行那一侧要编码，两处是否被服务端一致接受是实测档（M2），不在向量档里假装已经证明。
  let got = signed(
    "GET",
    "/中文 目录/+x%y&z.txt",
    [],
    [("host", vector_host)],
  )
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=host&q-url-param-list=&q-signature=28cf3c6cacfb3013e3cc2974691d6b497f39358a",
  )
}

///|
test "prefix, delimiter and encoding-type all take part in the signature" {
  let got = signed(
    "GET",
    "/",
    [
      ("prefix", "moonfs/含 空格&=+"),
      ("delimiter", "/"),
      ("max-keys", "100"),
      ("encoding-type", "url"),
    ],
    [("host", vector_host)],
  )
  assert_eq(
    got,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=" +
    vector_time +
    "&q-key-time=" +
    vector_time +
    "&q-header-list=host&q-url-param-list=delimiter;encoding-type;max-keys;prefix" +
    "&q-signature=a32020947d820b234bb1ebc46ea714dfe05a22d2",
  )
}

///|
test "sign_host=false really takes the host out of the string, and the empty list stays written" {
  let credentials = Credentials::new(vector_id, vector_key)
  let without_host = authorization(
    credentials,
    RequestToSign::{
      verb: "GET",
      path: "/a.txt",
      query: [],
      headers: [("host", vector_host)],
    },
    vector_window(),
    sign_host=false,
  )
  assert_true(without_host.has_prefix("q-sign-algorithm=sha1&q-ak=" + vector_id))
  assert_true(without_host.find("&q-header-list=&q-url-param-list=&q-signature=") is Some(_))
}

///|
/// 这一档的期望值是 oracle **就这条 path 现算**的：签名与 `/a.txt` 那档不同，
/// 不能拿别档的数字复用（起草时就是这么抄错的一次，红在测试而不是红在实现）。
test "the presigned form moves all seven fields into the query and escapes the semicolons" {
  let credentials = Credentials::new(vector_id, vector_key)
  let query = presign_query(
    credentials,
    RequestToSign::{
      verb: "GET",
      path: "/moonfs/notes.txt",
      query: [("acl", "")],
      headers: [("host", vector_host)],
    },
    vector_window(),
  )
  assert_eq(
    query,
    "q-sign-algorithm=sha1&q-ak=" +
    vector_id +
    "&q-sign-time=1760000000%3B1760000600&q-key-time=1760000000%3B1760000600" +
    "&q-header-list=host&q-url-param-list=acl&q-signature=" +
    "ef139cb01e879139c4ff9d6e533e73a80984c688",
  )
}

///|
test "a window that ends before it starts is refused locally, before any request" {
  let credentials = Credentials::new(vector_id, vector_key)
  let refused = try {
    let _ = presign_query(
      credentials,
      RequestToSign::{ verb: "GET", path: "/", query: [], headers: [] },
      { start: 1760000600L, end: 1760000000L, },
    )
    "no-error"
  } catch {
    @error.CosError::BadParam(m) => "BadParam:" + m
    _ => "other"
  }
  assert_true(refused.has_prefix("BadParam:"))
}

///|
test "empty credentials are refused at construction, and no output string carries the key" {
  let refused = try {
    let _ = Credentials::new("", "x")
    "no-error"
  } catch {
    @error.CosError::BadParam(m) => "BadParam:" + m
    _ => "other"
  }
  assert_true(refused.has_prefix("BadParam:"))
  let line = signed("GET", "/x", [], [("host", vector_host)])
  assert_true(line.find(vector_key) is None)
  assert_true(line.find(vector_id) is Some(_))
}
