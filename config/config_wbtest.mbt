///|
/// 寻址与编码这两档本地能钉死的部分：host 模板、桶名形状判据、**签的那一串与发的那一串
/// 本来就该不同形**。后者只钉形状差，不假装证明服务端接受这个差——那是实测档 M2。
let probe_bucket = "examplebucket-1250000000"

///|
let probe_region = "ap-guangzhou"

///|
fn probe_config() -> Config raise {
  let credentials = @auth.Credentials::new("AKIDtestid", "testSecretKey")
  Config::new(probe_region, credentials)
}

///|
fn refused(f : () -> Unit raise @error.CosError) -> String {
  try {
    f()
    "no-error"
  } catch {
    err =>
      match err {
        @error.CosError::BadParam(m) => "BadParam:" + m
        _ => "other"
      }
  }
}

///|
test "the host is the long bucket name plus the region, and nothing else" {
  let config = probe_config()
  assert_eq(
    config.host(probe_bucket),
    "examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com",
  )
  // 桶名里的 appid 就是寻址的一部分：这里不拆、不补、不另开一个配置项
  assert_eq(config.region(), probe_region)
}

///|
test "a bucket without an appid is refused locally, not answered with NoSuchBucket remotely" {
  assert_true(
    refused(() => validate_bucket("no-appid-here")).has_prefix("BadParam:"),
  )
  assert_true(
    refused(() => validate_bucket("name-not-digits")).has_prefix("BadParam:"),
  )
  assert_true(refused(() => validate_bucket("name-")).has_prefix("BadParam:"))
  assert_true(
    refused(() => validate_bucket("-1250000000")).has_prefix("BadParam:"),
  )
  // 名字自己带连字符是合法的，只有**最后一段**必须是纯数字
  let _ = validate_bucket("my-multi-part-name-1250000000")
}

///|
test "an empty region is refused: the region is the host, and a blank one cannot be fixed later" {
  let credentials = @auth.Credentials::new("AKIDtestid", "testSecretKey")
  let got = refused(() => {
    let _ = Config::new("   ", credentials)
  })
  assert_true(got.has_prefix("BadParam:"))
}

///|
test "the request line encodes each key segment and keeps the slashes" {
  assert_eq(
    encode_key("中文 目录/a b.txt"),
    "%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95/a%20b.txt",
  )
  // `+` `%` `&` `?` 全都要编——留任何一个都会在服务端变成另一个键
  assert_eq(encode_key("+x%y&z.txt"), "%2Bx%25y%26z.txt")
  assert_eq(encode_key(""), "")
  assert_eq(encode_key("a/b/c"), "a/b/c")
}

///|
test "the signature takes the decoded path: the two forms are deliberately not the same string" {
  let key = "中文 目录/+x%y&z.txt"
  assert_eq(path_of(key), "/" + key)
  assert_eq(path_of(""), "/")
  // 这一条钉的是"两处不同形"这个设计本身；服务端是否一致接受两处属实测档 M2
  assert_true(path_of(key) != "/" + encode_key(key))
  let config = probe_config()
  assert_eq(
    config.url_of(probe_bucket, key),
    "https://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com/" +
    "%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95/%2Bx%25y%26z.txt",
  )
}

///|
/// 自定义域名（已绑桶）那一档的形状。真桶依据：`http://<域名>/<key>` 由 `Server: tencent-cos`
/// 亲口应答（put/stat/读回/预签名/delete 全过），而 `桶名.<域名>` 根本不解析，https 停在
/// "目标主要名称不正确"的 TLS 握手——所以这一档的三条纪律都得钉住：host 逐字用、scheme 跟着
/// endpoint 前缀走、区域端点那条不许被带歪。
fn probe_domain_config(endpoint : String) -> Config raise @error.CosError {
  Config::with_domain(
    endpoint,
    probe_region,
    @auth.Credentials::new("AKIDtestid", "testSecretKey"),
  )
}

///|
test "a bound custom domain is used verbatim: no bucket prefix, scheme from the endpoint" {
  let http_domain = probe_domain_config("http://cos.example.com")
  assert_eq(http_domain.scheme(), "http")
  assert_true(http_domain.is_domain_style())
  // 域名模式下桶名不参与寻址——传什么桶名都到同一个 host（真桶上这就是那一个绑定的桶）
  assert_eq(http_domain.host(probe_bucket), "cos.example.com")
  assert_eq(http_domain.host(""), "cos.example.com")
  assert_eq(http_domain.host("别的-1250000000"), "cos.example.com")
  // 发出去的那一串：scheme + 域名 + 编码后的键（键的编码规则与虚主机档一字相同）
  assert_eq(
    http_domain.url_of(probe_bucket, "a b/c+d.png"),
    "http://cos.example.com/a%20b/c%2Bd.png",
  )
  // 不给前缀时落 https：把明文当默认值等于替调用方决定一件他可能没打算做的事
  let bare = probe_domain_config("cos.example.com")
  assert_eq(bare.scheme(), "https")
  assert_eq(bare.host(probe_bucket), "cos.example.com")
  // 尾斜杠可以带（控制台域名常这么写），带路径尾巴不行
  let slashed = probe_domain_config("https://cos.example.com/")
  assert_eq(slashed.host(probe_bucket), "cos.example.com")
  // 区域端点那条路不受影响：域名档之外一切照旧
  let region_config = probe_config()
  assert_true(!region_config.is_domain_style())
  assert_eq(
    region_config.host(probe_bucket),
    "examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com",
  )
}

///|
test "the signed path is the same object in both addressing modes" {
  // COS 签的就是请求路径本身（`/<key>`），桶名只在 host 里——换档不动签名面这一条
  let key = "中文 目录/+x%y&z.txt"
  let domain_side = probe_domain_config("http://cos.example.com")
  let region_side = probe_config()
  assert_eq(path_of(key), "/" + key)
  let domain_wire = domain_side.url_of(probe_bucket, key)
  let region_wire = region_side.url_of(probe_bucket, key)
  let tail = "/%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95/%2Bx%25y%26z.txt"
  assert_true(domain_wire.has_suffix(tail))
  assert_true(region_wire.has_suffix(tail))
  // 跨桶复制的源**永远**走区域虚主机：域名只绑定它自己那一个桶，拿它表达别的桶会静默指错
  assert_eq(
    domain_side.canonical_host("other-1250000000"),
    "other-1250000000.cos.ap-guangzhou.myqcloud.com",
  )
}

///|
test "a malformed custom domain is refused locally, never silently repaired" {
  assert_eq(
    refused(() => {
      let _ = probe_domain_config("http://")
    }),
    "BadParam:endpoint host is not usable: ",
  )
  let sneaky = refused(() => {
    let _ = probe_domain_config("https://cos.example.com/sneaky")
  })
  assert_true(
    sneaky.has_prefix("BadParam:endpoint carries a path after the host"),
  )
  assert_eq(
    refused(() => {
      let _ = probe_domain_config("  ")
    }),
    "BadParam:endpoint is empty",
  )
  // 域名档仍然要区域：签名面用不到它，但 `region()` 与复制源的派生要用，留空串是埋雷
  assert_true(
    refused(() => {
      let _ = Config::with_domain(
        "http://cos.example.com",
        "  ",
        @auth.Credentials::new("AKIDtestid", "testSecretKey"),
      )
    }).has_prefix("BadParam:region is required"),
  )
}
