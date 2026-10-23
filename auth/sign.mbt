///|
/// COS 原生签名（XML API 那一套 `q-sign-*`）。
///
/// 五步全部照三份官方 SDK 逐字对齐（Go `auth.go` 的 `newAuthorization`／
/// `genFormatParameters`／`genFormatHeaders`／`genAuthorization`，Python `cos_auth.py`，
/// JS `util.js` 的 `getAuth`）：
///
/// ```text
/// KeyTime = SignTime  = "<start>;<end>"        # 两串永远相等
/// SignKey             = hex(HMAC-SHA1(key=SecretKey, msg=KeyTime))
/// HttpRequestInfo     = method + "\n" + path + "\n" + Params + "\n" + Headers + "\n"
/// StringToSign        = "sha1" + "\n" + KeyTime + "\n" + hex(SHA1(HttpRequestInfo)) + "\n"
/// Signature           = hex(HMAC-SHA1(key=SignKey, msg=StringToSign))
/// ```
///
/// 与隔壁 `moon-oss` 的 OSS V4 **反着来**的四处，都在这个文件里有对应的档：
/// 签名里的 path 是**解码态**（OSS 签的是编码后的 CanonicalURI）；空值参数写成 `acl=`
/// 而不是光一个键名（OSS 不带 `=`）；`Host` 默认**进签**（OSS 把 host 算进头块当场红）；
/// 签名串里没有区域与密钥派生链（OSS 是四层 HMAC-SHA256 加 `aliyun_v4_request` scope）。
/// 照抄上一代一定红，所以每一处都钉了用例。

///|
/// 一对密钥。`secret_id` 会原样进 `q-ak`（预签名 URL 里也是明文，所以它不是秘密），
/// `secret_key` 只进 HMAC，永不出现在任何输出串里。
pub struct Credentials {
  priv secret_id : String
  priv secret_key : String
  priv security_token : String?
}

///|
pub fn Credentials::new(
  secret_id : String,
  secret_key : String,
) -> Credentials raise @error.CosError {
  if secret_id.is_empty() || secret_key.is_empty() {
    raise @error.CosError::BadParam(
      "credentials need both a SecretId and a SecretKey",
    )
  }
  { secret_id, secret_key, security_token: None, }
}

///|
pub fn Credentials::secret_id(self : Credentials) -> String {
  self.secret_id
}

///|
/// 挂一把 STS 临时令牌；空串视作"不挂"，返回自身。
pub fn Credentials::with_security_token(
  self : Credentials,
  token : String,
) -> Credentials {
  if token.is_empty() {
    self
  } else {
    {
      secret_id: self.secret_id,
      secret_key: self.secret_key,
      security_token: Some(token),
    }
  }
}

///|
pub fn Credentials::security_token(self : Credentials) -> String? {
  self.security_token
}

///|
/// 签名窗口。起始时刻**往前回拨 60 秒**、结束时刻是 `now + expires`——这是参照实现对
/// 时钟漂移的容忍姿势（Go 与 JS 各减 60 与 1 秒，取最宽那档）。服务端按自己的时钟判
/// 这个区间，偏差超过 15 分钟就回 403 `RequestTimeTooSkewed`。
pub struct Window {
  start : Int64
  end : Int64
}

///|
pub fn Window::text(self : Window) -> String {
  self.start.to_string() + ";" + self.end.to_string()
}

///|
pub fn window_at(millis : Int64, expires : Int64) -> Window {
  let now = millis / 1000
  let start = now - 60
  let end = now + expires
  { start, end, }
}

///|
pub fn now_millis() -> Int64 {
  @date.now_millis()
}

///|
/// 一条待签请求。`path` 是**解码态**的请求路径（虚主机寻址下就是 `/` 或 `/<key>`，
/// 桶名在 host 里、不进签名）；`query` 与 `headers` 允许同一个键出现多次。
pub(all) struct RequestToSign {
  verb : String
  path : String
  query : Array[(String, String)]
  headers : Array[(String, String)]
}

///|
/// 不编码集只有 `A-Za-z0-9` 与 `- _ . ~`，其余一律 `%XX`（大写十六进制）、空格是 `%20`。
/// core 的 percent 正好是这一档——它比 JS 的 `encodeURIComponent` 严，把 `! ' ( ) *`
/// 也编掉了，而参照实现正是靠五次手工 replace 把它们补回去的。
pub fn cos_encode(text : String) -> String {
  @percent.encode(text.view())
}

///|
/// 键名的形态：先编码再整体小写（参照实现同序）。ASCII 键名编不动，所以这一步对
/// 头名与参数名等价于小写；顺序写反了会在非 ASCII 键上分家。
fn key_form(key : String) -> String {
  cos_encode(key).to_lower()
}

///|
/// 码位逐位比较，折成 -1/0/1。不能用 core 的 `String.compare`：它先比长度再比内容，
/// 拿来排序会把 `b` 排到 `aa` 后面，签名当场对不上。
fn compare_units(a : String, b : String) -> Int32 {
  let ac = a.to_array()
  let bc = b.to_array()
  let shared = if ac.length() < bc.length() { ac.length() } else { bc.length() }
  let mut i = 0
  while i < shared {
    if ac[i] < bc[i] {
      return -1
    }
    if ac[i] > bc[i] {
      return 1
    }
    i = i + 1
  }
  if ac.length() == bc.length() {
    0
  } else if ac.length() < bc.length() {
    -1
  } else {
    1
  }
}

///|
/// 先按编码后的小写键名排，键相同再按**未编码的原值**排（参照实现正是这个次序：
/// 值原样收进桶、渲染时才编码）。
fn compare_pair(a : (String, String), b : (String, String)) -> Int32 {
  let by_key = compare_units(a.0, b.0)
  if by_key != 0 {
    by_key
  } else {
    compare_units(a.1, b.1)
  }
}

///|
fn sort_pairs(pairs : Array[(String, String)]) -> Array[(String, String)] {
  let out = pairs.copy()
  let mut i = 1
  while i < out.length() {
    let mut j = i
    while j > 0 && compare_pair(out[j - 1], out[j]) > 0 {
      let left = out[j - 1]
      out[j - 1] = out[j]
      out[j] = left
      j = j - 1
    }
    i = i + 1
  }
  out
}

///|
/// 规范化出来两段：`body` 进签名串，`keys` 是 `q-header-list`／`q-url-param-list` 的字面。
///
/// 三个容易写错的点，逐条对着参照实现钉住：
/// ① 排序发生在**编码前的原值**上（参照实现把值原样收进桶、渲染时才编码），值也要排；
/// ② 同一个键出现多次时，`keys` 里**重复出现**（参照实现是每收一个值追加一次键名），
///    不走去重；
/// ③ 空值仍然渲染成 `k=`，等号不能省。
priv struct Canonical {
  body : String
  keys : String
}

///|
fn canonicalize(pairs : Array[(String, String)]) -> Canonical {
  let bodies : Array[String] = []
  let keys : Array[String] = []
  for pair in sort_pairs(pairs) {
    bodies.push(pair.0 + "=" + cos_encode(pair.1))
    keys.push(pair.0)
  }
  { body: bodies.join("&"), keys: keys.join(";"), }
}

///|
/// 能进签的头名单（Go 那份 `NeedSignHeaders` 最全，按它对齐），外加 `x-cos-`／`x-ci-`
/// 两个前缀（STS 的 `x-cos-security-token` 就是靠前缀自动入签的，不需要特判）。
/// 名单外的头**不参与签名**，这是原生与 SigV4 的另一处差别：SigV4 里没进
/// `SignedHeaders` 的头是调用方显式选的，这里是实现侧写死的白名单。
fn is_signable_header(lowered : String) -> Bool {
  match lowered {
    "host" => true
    "range" => true
    "cache-control" => true
    "content-disposition" => true
    "content-encoding" => true
    "content-type" => true
    "content-length" => true
    "content-md5" => true
    "transfer-encoding" => true
    "expect" => true
    "expires" => true
    "if-match" => true
    "if-modified-since" => true
    "if-none-match" => true
    "if-unmodified-since" => true
    "origin" => true
    "access-control-request-method" => true
    "access-control-request-headers" => true
    "pic-operations" => true
    "x-cos-acl" => true
    "x-cos-grant-read" => true
    "x-cos-grant-write" => true
    "x-cos-grant-full-control" => true
    "x-cos-content-sha1" => true
    "x-cos-storage-class" => true
    "x-cos-object-type" => true
    _ => lowered.has_prefix("x-cos-") || lowered.has_prefix("x-ci-")
  }
}

///|
/// 只留白名单内的头。`sign_host=false` 那一档是给自定义域名（CNAME／CDN 前置）留的口子：
/// 原生签名默认把 `Host` 算进去，换了访问域名签名就跟着变，参照实现自己也只写了
/// "可能失败或有安全风险"。实测那一半：备案后的自定义域名在 80 端口能路由进桶，
/// 但 443 的证书名盖不住；签虚主机的预签名换域名直接拒，只有不签 `Host` 的那条能跨域名用。
fn signable_headers(
  headers : Array[(String, String)],
  sign_host~ : Bool,
) -> Array[(String, String)] {
  let kept : Array[(String, String)] = []
  for pair in headers {
    let lowered = pair.0.to_lower()
    let is_host = lowered == "host"
    if is_host {
      if sign_host {
        kept.push((key_form(pair.0), pair.1))
      }
    } else if is_signable_header(lowered) {
      kept.push((key_form(pair.0), pair.1))
    }
  }
  kept
}

///|
fn signable_query(query : Array[(String, String)]) -> Array[(String, String)] {
  let kept : Array[(String, String)] = []
  for (key, value) in query {
    kept.push((key_form(key), value))
  }
  kept
}

///|
/// 四行式规范化请求串。**这里用调用方给的解码态 path**，不做任何编码——发出去的请求行
/// 才需要百分号编码，两处不一致是本家协议最反直觉的一条（实测档见 §2.4 的 M2）。
pub fn format_string(
  verb : String,
  path : String,
  params : String,
  headers : String,
) -> String {
  verb.to_lower() + "\n" + path + "\n" + params + "\n" + headers + "\n"
}

///|
/// `StringToSign` 的第一行恒为 `sha1`：三份官方 SDK 都把这个算法写死（Go 的 `switch` 只有
/// `"sha1"` 一个 case，default 也回落到 sha1），端点收不收 `sha256` 属实测档，本模块**不提供**
/// 那一档——没有参照实现的行为不写进公开面。
/// 第二行用的是 `q-key-time` 那一串。参照实现两处传的确实是同一个值
/// （Go 的 `calStringToSign(algo, keyTime, formatString)`），而 Authorization 里
/// `q-sign-time` 与 `q-key-time` 也永远相等——把它们写成不等，签名当场就废。
pub fn string_to_sign(key_time : String, format : String) -> String {
  "sha1" + "\n" + key_time + "\n" + @digest.sha1_hex(format) + "\n"
}

///|
/// 派生 SignKey：HMAC-SHA1 的**密钥是 SecretKey、消息是时间窗**。参照三家在这个
/// 参数序上一致（JS 那边写成 `HmacSHA1(msg, key)` 是因为 CryptoJS 的实参序本来就相反）。
pub fn sign_key(secret_key : String, key_time : String) -> String {
  @digest.hmac_sha1_hex(secret_key, key_time)
}

///|
pub fn signature(key : String, msg : String) -> String {
  @digest.hmac_sha1_hex(key, msg)
}

///|
/// 完整的 `Authorization` 值：**无 scheme 前缀、无空格**，七个字段用 `&` 连，
/// 两个 list 内部用 `;` 连；两个 list 为空时字段仍要写（值是空串）。
pub fn authorization(
  credentials : Credentials,
  request : RequestToSign,
  window : Window,
  sign_host~ : Bool = true,
) -> String {
  let time = window.text()
  let params = canonicalize(signable_query(request.query))
  let headers = canonicalize(signable_headers(request.headers, sign_host~))
  let format = format_string(
    request.verb,
    request.path,
    params.body,
    headers.body,
  )
  let to_sign = string_to_sign(time, format)
  let derived = sign_key(credentials.secret_key, time)
  let digest = signature(derived, to_sign)
  "q-sign-algorithm=sha1" +
  "&q-ak=" +
  credentials.secret_id +
  "&q-sign-time=" +
  time +
  "&q-key-time=" +
  time +
  "&q-header-list=" +
  headers.keys +
  "&q-url-param-list=" +
  params.keys +
  "&q-signature=" +
  digest
}
