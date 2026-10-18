///|
/// 寻址与编码这两档本地能钉死的部分：host 模板、桶名形状判据、**签的那一串与发的那一串
/// 本来就该不同形**。后者只钉形状差，不假装证明服务端接受这个差——那是实测档 M2。
let probe_bucket = "mldong-test-1251150780"

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
    "mldong-test-1251150780.cos.ap-guangzhou.myqcloud.com",
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
    "https://mldong-test-1251150780.cos.ap-guangzhou.myqcloud.com/" +
    "%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95/%2Bx%25y%26z.txt",
  )
}
