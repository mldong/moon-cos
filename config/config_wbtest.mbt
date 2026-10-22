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
/// "目标主要名称不正确"的 TLS 握手——所以这一档的三条纪律都得钉住：host 逐字用、scheme 由
/// endpoint 前缀或显式 `scheme~` 定（两处冲突就地拒）、区域端点那条不许被带歪。
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

///|
/// scheme 的两条写法（endpoint 前缀 / 显式 `scheme~`）各自都合法，但只能表达一个意思。
/// 判据分四种：一致→用它；只写了一处→用那一处；两处都没写→`https`；两处打架→就地拒，
/// 而不是让后写的那一处悄悄赢（默认值一旦写成 `"https"`，`http://…` 这种合法输入就会被
/// 误判成冲突，所以"没写"与"写了 https"在类型上必须是两回事）。
/// 值先 trim 再判，与 endpoint/domain 串同一条规矩；报错文案里报的是**给到的原串**，
/// 不是 trim 后的那一份。
fn probe_scheme_config(
  endpoint : String,
  scheme : String,
) -> Config raise @error.CosError {
  Config::with_domain(
    endpoint,
    probe_region,
    @auth.Credentials::new("AKIDtestid", "testSecretKey"),
    scheme~,
  )
}

///|
test "an explicit scheme~ is the one that wins when the endpoint says nothing" {
  let plain = probe_scheme_config("cos.example.com", "http")
  assert_eq(plain.scheme(), "http")
  assert_eq(plain.url_of(probe_bucket, "k.txt"), "http://cos.example.com/k.txt")
  let secure = probe_scheme_config("cos.example.com", "https")
  assert_eq(secure.scheme(), "https")
  assert_eq(
    secure.url_of(probe_bucket, "k.txt"),
    "https://cos.example.com/k.txt",
  )
  // 两处都没写才落 https（默认值是空串，不是 "https"）
  assert_eq(probe_scheme_config("cos.example.com", "").scheme(), "https")
  // 与 endpoint 串同一条规矩：先 trim 再判值（这一格常从环境变量里来，带个尾空格
  // 不该读成"给了一个非法 scheme"）
  assert_eq(probe_scheme_config("cos.example.com", " http ").scheme(), "http")
}

///|
test "the endpoint prefix and scheme~ agree or are refused, never silently reconciled" {
  // 一致：两种写法同一意思，照用
  let both_http = probe_scheme_config("http://cos.example.com", "http")
  assert_eq(both_http.scheme(), "http")
  let both_https = probe_scheme_config("https://cos.example.com", "https")
  assert_eq(both_https.scheme(), "https")
  // 打架：响亮拒，报错里带上两处各自的读法，别让人猜哪一处赢了
  let wrong_way = refused(() => {
    let _ = probe_scheme_config("http://cos.example.com", "https")
  })
  assert_true(
    wrong_way.has_prefix("BadParam:scheme conflicts with the endpoint"),
  )
  assert_true(wrong_way.contains("prefix-scheme=http scheme=https"))
  let other_way = refused(() => {
    let _ = probe_scheme_config("https://cos.example.com", "http")
  })
  assert_true(other_way.contains("prefix-scheme=https scheme=http"))
}

///|
test "a scheme that is neither http nor https is refused in both addressing modes" {
  for bad in ["ftp", "HTTP", "http s", "https://"] {
    let got = refused(() => {
      let _ = probe_scheme_config("cos.example.com", bad)
    })
    assert_true(
      got.has_prefix("BadParam:scheme must be http or https, got: " + bad),
    )
    let region_got = refused(() => {
      let _ = Config::new(
        probe_region,
        @auth.Credentials::new("AKIDtestid", "testSecretKey"),
        scheme=bad,
      )
    })
    assert_true(
      region_got.has_prefix(
        "BadParam:scheme must be http or https, got: " + bad,
      ),
    )
  }
  // 文案里报的是**给到的原串**：trim 只用来判值，报出来还带着那两个空格，
  // 才看得清 env 里那一格到底写了什么
  assert_true(
    refused(() => {
      let _ = probe_scheme_config("cos.example.com", " ftp ")
    }).has_suffix(" ftp "),
  )
}

///|
test "the region endpoint takes scheme~ too, and its default is unchanged" {
  let credentials = @auth.Credentials::new("AKIDtestid", "testSecretKey")
  // 默认那一档与抬 `scheme~` 之前逐字相同：老调用点不会因为多了一个可选参数而换协议
  let default_config = Config::new(probe_region, credentials) catch {
    e => abort(e.text())
  }
  assert_eq(default_config.scheme(), "https")
  assert_true(!default_config.is_domain_style())
  assert_eq(
    default_config.url_of(probe_bucket, "k.txt"),
    "https://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com/k.txt",
  )
  // 显式明文那一档只服务代理／内网镜像／抓包：host 仍按虚主机派生，scheme 换掉
  let plain = Config::new(probe_region, credentials, scheme="http") catch {
    e => abort(e.text())
  }
  assert_eq(plain.scheme(), "http")
  assert_eq(
    plain.url_of(probe_bucket, "k.txt"),
    "http://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com/k.txt",
  )
  // 区域端点档没有 endpoint 前缀可冲突：`scheme~` 单独就是最终值
  assert_eq(plain.host(probe_bucket), default_config.host(probe_bucket))
}
