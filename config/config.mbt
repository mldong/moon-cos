///|
/// COS 的寻址只有一个答案：**虚主机**，host 里带桶名（长命名 `<Name>-<APPID>`），path 里
/// 只有对象键。path 风格（把桶名放在 path 上）2024-01-01 之后建的桶一律 403
/// `PathStyleDomainForbidden`，所以这里不给开关——给了也只是多一条会红的配置。
///
/// 与隔壁 `moon-oss` 的第二处分叉：OSS 签的 CanonicalURI **含桶名**（`/<bucket>/<key>`），
/// COS 签的就是**请求路径本身**（`/<key>`），桶名只在 host 里。
pub struct Config {
  priv region : String
  priv credentials : @auth.Credentials
}

///|
pub fn Config::new(
  region : String,
  credentials : @auth.Credentials,
) -> Config raise @error.CosError {
  let trimmed = region.trim().to_owned()
  if trimmed.is_empty() {
    raise @error.CosError::BadParam(
      "region is required: it is the host, not the signature",
    )
  }
  { region: trimmed, credentials, }
}

///|
pub fn Config::region(self : Config) -> String {
  self.region
}

///|
pub fn Config::credentials(self : Config) -> @auth.Credentials {
  self.credentials
}

///|
/// 桶名的形状判据：COS 的桶一律是 `<Name>-<APPID>`，appid 是一段纯数字。
/// 少了这一截，拼出来的 host 永远指不到任何桶——与其让服务端回一句
/// `NoSuchBucket`（那个域照样解析、照样应答），不如在本地响亮拒绝。
pub fn validate_bucket(bucket : String) -> Unit raise @error.CosError {
  let parts = bucket.split("-").collect()
  let last = parts.length() - 1
  if last < 1 {
    raise @error.CosError::BadParam(
      "bucket must be the long form <Name>-<APPID>: " + bucket,
    )
  }
  let appid = parts[last].to_owned()
  if appid.is_empty() {
    raise @error.CosError::BadParam(
      "bucket must carry an appid after the dash: " + bucket,
    )
  }
  for ch in appid.to_array() {
    let code = ch.to_int()
    if code < 48 || code > 57 {
      raise @error.CosError::BadParam(
        "the part after the last dash must be digits (the appid): " + bucket,
      )
    }
  }
  if parts[0].to_owned().is_empty() {
    raise @error.CosError::BadParam(
      "bucket name is empty before the appid: " + bucket,
    )
  }
}

///|
pub fn Config::host(
  self : Config,
  bucket : String,
) -> String raise @error.CosError {
  validate_bucket(bucket)
  bucket + ".cos." + self.region + ".myqcloud.com"
}

///|
/// 对象键编码成请求行里那一段：按 `/` 分段编码，斜杠本身保留（整串编码会把 `a/b` 变成
/// `a%2Fb`，那是另一个键）。签名用的**不是**这一串，见 `path_of`。
pub fn encode_key(key : String) -> String {
  let out : Array[String] = []
  for segment in key.split("/") {
    out.push(@percent.encode(segment))
  }
  out.join("/")
}

///|
pub fn Config::url_of(
  self : Config,
  bucket : String,
  key : String,
) -> String raise @error.CosError {
  "https://" + self.host(bucket) + "/" + encode_key(key)
}

///|
/// 签名里的 path：`/` 或 `/<key>`，**解码态原样**（非 ASCII 就直接进签名串）。
/// 这是本家协议最反直觉的一条——签的是这一串，发出去的是 `encode_key` 那一串。
/// 两处是否被服务端一致接受属实测档（阶段 H 卡 §2.4 的 M2），别照 SigV4/OSS V4 的习惯编码。
pub fn path_of(key : String) -> String {
  if key.is_empty() {
    "/"
  } else {
    "/" + key
  }
}
