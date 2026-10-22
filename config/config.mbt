///|
/// COS 的默认寻址是**虚主机**：host 里带桶名（长命名 `<Name>-<APPID>`），path 里只有对象键。
/// path 风格（把桶名放在 path 上）2024-01-01 之后建的桶一律 403
/// `PathStyleDomainForbidden`，所以区域端点这一档不给开关——给了也只是多一条会红的配置。
///
/// 另一档是**自定义域名**（[Config::with_domain]）：域名在控制台里已经绑定某一个桶，
/// 所以 host 逐字用、**不许再拼桶名**。2026-10-21 真桶实测两条：`桶名.<域名>` 根本不解析
/// （NXDOMAIN），而 `http://<域名>/<key>` 由 `Server: tencent-cos` 亲口应答——即这一档走
/// 明文是通的，https 要等桶侧把证书绑上（没绑时停在 TLS 握手）。
///
/// 与隔壁 `moon-oss` 的第二处分叉：OSS 签的 CanonicalURI **含桶名**（`/<bucket>/<key>`），
/// COS 签的就是**请求路径本身**（`/<key>`），桶名只在 host 里。两条签名都不含 scheme，
/// 所以 http 与 https 之间换档不动签名面。
pub struct Config {
  priv region : String
  priv credentials : @auth.Credentials
  priv scheme : String
  priv domain : String?
}

///|
/// 服务级主机（`GET /` 列桶那一发用）。
pub let service_host : String = "service.cos.myqcloud.com"

///|
/// 区域端点那一档。scheme 默认 https；`scheme~="http"` 是给代理／内网镜像／抓包这类
/// 非常规路径用的，接真桶没有理由用它。
pub fn Config::new(
  region : String,
  credentials : @auth.Credentials,
  scheme~ : String = "",
) -> Config raise @error.CosError {
  let trimmed = trim_region(region)
  let chosen = resolve_scheme(None, scheme, "region endpoint")
  { region: trimmed, credentials, scheme: chosen, domain: None, }
}

///|
/// 自定义域名那一档：`domain` 接受带或不带 scheme 两种写法（`cdn.example.com` /
/// `http://cdn.example.com`）；没给前缀又没给 `scheme~` 时默认 `https`——把明文当默认值
/// 等于替调用方决定一件他可能没打算做的事。带 `//` 之后 authority 为空、或主机后面还带
/// 路径尾巴的一律 `BadParam`：那种输入十有八九是把控制台"访问域名"整串粘了过来，静默剥掉
/// 会让请求打到错误的桶。
pub fn Config::with_domain(
  domain : String,
  region : String,
  credentials : @auth.Credentials,
  scheme~ : String = "",
) -> Config raise @error.CosError {
  let trimmed_region = trim_region(region)
  let (prefix, host) = split_endpoint(domain)
  let chosen = resolve_scheme(prefix, scheme, domain)
  { region: trimmed_region, credentials, scheme: chosen, domain: Some(host), }
}

///|
fn trim_region(region : String) -> String raise @error.CosError {
  let trimmed = region.trim().to_owned()
  if trimmed.is_empty() {
    raise @error.CosError::BadParam(
      "region is required: it is the host, not the signature",
    )
  }
  trimmed
}

///|
/// scheme 的两种写法（endpoint 前缀 / 显式 `scheme~`）都合法，但只能表达一个意思。
/// `prefix` 是 `None` 表示串里**没写**前缀（不是写了 https），那种情况由 `given` 定，
/// 两者都没定才落 `https`。把默认值写成 `"https"` 会把 `http://…` 这种合法输入误判成冲突。
fn resolve_scheme(
  prefix : String?,
  given : String,
  endpoint_desc : String,
) -> String raise @error.CosError {
  let trimmed = given.trim().to_owned()
  if trimmed.is_empty() {
    match prefix {
      None => "https"
      Some(p) => p
    }
  } else if trimmed != "http" && trimmed != "https" {
    raise @error.CosError::BadParam(
      "scheme must be http or https, got: " + given,
    )
  } else {
    let prefix_value = match prefix {
      None => trimmed
      Some(p) => p
    }
    if prefix_value != trimmed {
      raise @error.CosError::BadParam(
        "scheme conflicts with the endpoint prefix: endpoint=" +
        endpoint_desc +
        " prefix-scheme=" +
        prefix_value +
        " scheme=" +
        trimmed,
      )
    }
    trimmed
  }
}

///|
/// 从 endpoint 串里拆出 **scheme 前缀**（没写就是 `None`，与"写了 https"是两回事）与主机。
/// 主机的合法性只判到这里（空 authority、带路径尾巴、含空格）：域名解析与证书是服务端与
/// 桶侧配置的事，本地不冒充知道。
fn split_endpoint(endpoint : String) -> (String?, String) raise @error.CosError {
  let trimmed = endpoint.trim().to_owned()
  if trimmed.is_empty() {
    raise @error.CosError::BadParam("endpoint is empty")
  }
  let prefix : String? = if trimmed.has_prefix("https://") {
    Some("https")
  } else if trimmed.has_prefix("http://") {
    Some("http")
  } else {
    None
  }
  let rest = match trimmed.find("://") {
    None => trimmed
    Some(cut) => trimmed[cut + 3:trimmed.length()].to_owned()
  }
  let host = match rest.find("/") {
    None => rest
    Some(cut) => {
      let tail = rest[cut + 1:rest.length()].to_owned()
      if !tail.is_empty() {
        raise @error.CosError::BadParam(
          "endpoint carries a path after the host: " + rest,
        )
      }
      rest[0:cut].to_owned()
    }
  }
  if host.is_empty() || host.contains(" ") {
    raise @error.CosError::BadParam("endpoint host is not usable: " + host)
  }
  (prefix, host)
}

///|
pub fn Config::region(self : Config) -> String {
  self.region
}

///|
/// 发请求时用的 scheme：两档都可以由调用方定（endpoint 前缀或显式 `scheme~`），都没定才落
/// `https`。签名不含 scheme，所以这一格换档不动签名面。
pub fn Config::scheme(self : Config) -> String {
  self.scheme
}

///|
/// 这一份 Config 是不是"自定义域名"档。下游（适配层、测试）拿它分档，别拿字符串猜。
pub fn Config::is_domain_style(self : Config) -> Bool {
  match self.domain {
    Some(_) => true
    None => false
  }
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
/// 区域端点上的主机：空桶名是服务级主机，其余一律 `<桶名>.cos.<区域>.myqcloud.com`。
/// **跨桶的那一发（复制源）永远走这里** —— 自定义域名只绑定它自己那一个桶，
/// 拿域名去表达"另一个桶"会静默指错地方。
pub fn Config::canonical_host(
  self : Config,
  bucket : String,
) -> String raise @error.CosError {
  if bucket.is_empty() {
    service_host
  } else {
    validate_bucket(bucket)
    bucket + ".cos." + self.region + ".myqcloud.com"
  }
}

///|
/// 这一发要打到哪个主机：域名档逐字用域名（桶名不参与，`<name>-<appid>` 那条校验也
/// 一并跳过——域名模式下那个串根本不进 host，拿它拦人只会拦掉本来能成的请求），
/// 其余档走区域端点的虚主机/服务级主机。
pub fn Config::host(
  self : Config,
  bucket : String,
) -> String raise @error.CosError {
  match self.domain {
    Some(domain) => domain
    None => self.canonical_host(bucket)
  }
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
  self.scheme + "://" + self.host(bucket) + "/" + encode_key(key)
}

///|
/// 签名里的 path：`/` 或 `/<key>`，**解码态原样**（非 ASCII 就直接进签名串）。
/// 这是本家协议最反直觉的一条——签的是这一串，发出去的是 `encode_key` 那一串。
/// 别照 SigV4/OSS V4 的习惯编码：真桶实测过含中文、空格、`%`、`+`、`&` 的键，两处被一致接受。
pub fn path_of(key : String) -> String {
  if key.is_empty() {
    "/"
  } else {
    "/" + key
  }
}
