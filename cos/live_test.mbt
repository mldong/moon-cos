///|
// 真端点档（凭据只从环境读，绝不打印值）。这一档才是阶段 H 卡 §2.4 那些待实测项的裁决处：
// 向量测试只能证明"我算得自洽"，真端点证明"COS 认这一串"。
//
// Env: COS_AK / COS_SK / COS_BUCKET / COS_REGION（外加可选的 COS_RUN_TAG，并行跑时区分前缀）。
// 缺任何一项整段响亮跳过。
//
// COS_DOMAIN 这里**故意不读**：自定义域名是个裸 CNAME、桶侧没备案（读数在阶段 H 卡 §1），
// 原生签名默认把 Host 算进去，换域名那条 URL 当场就废——所以腿用的是虚主机派生的域名。

///|
fn live_env() -> (String, String)? {
  let names : Array[String] = ["COS_AK", "COS_SK", "COS_BUCKET", "COS_REGION"]
  let missing : Array[String] = []
  for name in names {
    if @env.get_env_var(name).unwrap_or("").is_empty() {
      missing.push(name)
    }
  }
  if missing.length() > 0 {
    println("missing: " + missing.join(", "))
    None
  } else {
    Some(
      (
        @env.get_env_var("COS_AK").unwrap_or(""),
        @env.get_env_var("COS_SK").unwrap_or(""),
      ),
    )
  }
}

///|
fn skip_note() -> Unit {
  println("SKIP live COS check, COS_* not supplied")
  println(
    "SKIP IS NOT A PASS: the native COS signature was not measured by this run.",
  )
}

///|
fn bucket() -> String {
  @env.get_env_var("COS_BUCKET").unwrap_or("")
}

///|
fn region() -> String {
  @env.get_env_var("COS_REGION").unwrap_or("")
}

///|
fn prefix(label : String) -> String {
  let tag = @env.get_env_var("COS_RUN_TAG").unwrap_or("0")
  "moonfs-cos-" + label + "-" + tag
}

///|
fn build(
  ak : String,
  sk : String,
  cos_region : String,
) -> @cos.Client raise @error.CosError {
  let credentials = @auth.Credentials::new(ak, sk)
  let config = @config.Config::new(cos_region, credentials)
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  @cos.Client::new(config, transport)
}

///|
fn cos_text(error : @error.CosError) -> String {
  error.text()
}

///|
fn transport_text(error : @transport.TransportError) -> String {
  match error {
    @transport.TransportError::Network(msg) => "network: " + msg
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(msg) => "invalid request: " + msg
    @transport.TransportError::InvalidResponse(msg) =>
      "invalid response: " + msg
  }
}

///|
async fn drain(body : &@transport.ResponseBody) -> Bytes {
  let merged : Array[Byte] = []
  let mut reading = true
  while reading {
    let chunk = body.read(65536) catch {
      err => fail("read response body: " + transport_text(err))
    }
    match chunk {
      None => reading = false
      Some(data) => merged.append(data.to_array())
    }
  }
  body.close()
  Bytes::from_array(merged)
}

///|
/// 免凭据发一条请求：这一发不带任何 Authorization，能取回才叫"预签名"，
/// 被拒才叫"签名/窗口真在被校验"。返回状态码与正文。
async fn fetch_without_credentials(
  transport : &@transport.Transport,
  verb : @transport.Method,
  url : String,
  body~ : Bytes = Bytes::from_array([]),
) -> (Int32, Bytes) {
  let request_body = if body.is_empty() {
    @transport.RequestBody::Empty
  } else {
    @transport.RequestBody::Bytes(body)
  }
  let response = transport.send(@transport.Request::{
    http_method: verb,
    url,
    headers: [],
    body: request_body,
  }) catch {
    err => fail("unsigned request raised " + transport_text(err))
  }
  let status = response.status
  let read = drain(response.body)
  (status, read)
}

///|
/// 造 N 字节的正文。分片档每片不得低于 1 MiB（实测翻点），所以这里要能造到兆级——
/// 用一块 33 字节的料反复拼，不写循环里造字符串那种一兆次拼接。
fn filler(total : Int32) -> Bytes {
  let block = "moon-cos-filler-0123456789abcdef\n"
  let mut out = block
  while out.length() < total {
    out = out + out
  }
  @utf8.encode(out[0:total].to_owned())
}

///|
async test "对象族在真桶上往返，键里的中文/空格/百分号/加号/与号都签得动（M2、M13）" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let b = bucket()
      let root = prefix("object")
      let plain = root + "/notes.txt"
      let tricky = root + "/中文 目录/+x%y&z.txt"
      let body = @utf8.encode(
        "这一份正文要逐字节对照，尺寸不重要，形状才重要\n",
      )
      let written = client.put_object(
        b,
        plain,
        body,
        content_type="text/plain",
        metadata=[("tool", "moon-cos")],
      )
      assert_true(!written.etag.is_empty())
      let _ = client.put_object(b, tricky, body)

      let stat = client.stat_object(b, plain)
      println("etag 读数=" + stat.etag.unwrap_or("<none>"))
      assert_eq(stat.size, body.length().to_int64())
      assert_eq(stat.content_type.unwrap_or(""), "text/plain")
      assert_true(
        stat.metadata.length() == 1 && stat.metadata[0] == ("tool", "moon-cos"),
      )

      // M2 的裁决处：签名里是解码态 path，发出去的是编码态请求行。
      // 这一发要是不一致，键就对不上，读回来的是另一份或干脆 404。
      let got = client.get_object(b, tricky)
      assert_eq(got.body.to_array(), body.to_array())
      let sliced = client.get_object(b, plain, range="bytes=0-3")
      assert_eq(sliced.content_length, 4L)
      println("range 读数=" + sliced.content_range.unwrap_or("<none>"))

      // 列举带 encoding-type=url：回包的键是编码态，本 SDK 解回来后必须与写进去的逐字相同。
      // 这一档同时把"实体二次解码"那一路整段绕开了。
      let listing = client.list_objects(b, prefix=root)
      let keys : Array[String] = []
      for item in listing.objects {
        keys.push(item.key)
      }
      println("M9/列举条数=" + keys.length().to_string())
      assert_true(keys.contains(plain))
      assert_true(keys.contains(tricky))
      for item in listing.objects {
        if item.key == tricky {
          assert_eq(item.size, body.length().to_int64())
        }
      }

      let copied = client.copy_object(b, plain, b, root + "/copied.txt")
      println("copy 回执读数=" + copied.etag)
      assert_true(!copied.etag.is_empty())

      let _ = client.delete_object(b, plain)
      let _ = client.delete_object(b, tricky)
      let _ = client.delete_object(b, root + "/copied.txt")
      // M13：HEAD 打不存在的键。判"不存在"只看状态码；正文与 Code 可能是空的，读数打出来。
      let absent = try {
        let _ = client.stat_object(b, plain)
        "no-error"
      } catch {
        err =>
          match err {
            @error.CosError::Service(details) => {
              println(
                "M13 读数：status=" +
                details.status.to_string() +
                " code=<" +
                details.code +
                "> trace_id 在场=" +
                (!details.trace_id.is_empty()).to_string(),
              )
              details.status.to_string()
            }
            _ => cos_text(err)
          }
      }
      assert_eq(absent, "404")
      assert_no_residue(client, root)
    }
  }
}

///|
async test "分片五步与完成件读数（M8、M9）" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let b = bucket()
      let root = prefix("multipart")
      let key = root + "/big.bin"
      let upload_id = client.create_multipart_upload(
        b,
        key,
        content_type="application/octet-stream",
      )
      println("uploadId 长度=" + upload_id.length().to_string())
      let piece = filler(1048576)
      let one = client.upload_part(b, key, upload_id, 1, piece)
      let two = client.upload_part(b, key, upload_id, 2, piece)
      let page = client.list_parts(b, key, upload_id)
      assert_eq(page.parts.length(), 2)
      assert_eq(page.parts[0].etag, one)
      // 每片必须真到 1 MiB：上一轮这条断言没写，filler 少拼了一倍、
      // 片成 540672 字节，红在 complete 的 EntityTooSmall 上而不是红在造料上。
      assert_eq(page.parts[0].size, 1048576L)
      assert_eq(page.parts[1].size, 1048576L)
      // M8：完成件**不发** Content-MD5。文档摘要说过它 required，而参照实现的 Python 那份
      // 根本不发——这一发就是裁决：收下来、对象尺寸对得上，才算定案。
      let done = client.complete_multipart_upload(b, key, upload_id, parts=[
        (1, one),
        (2, two),
      ])
      println("M9 读数：完成件 etag=" + done.etag)
      let stat = client.stat_object(b, key)
      assert_eq(stat.size, 2097152L)
      let _ = client.delete_object(b, key)

      let second = client.create_multipart_upload(b, root + "/abort.bin")
      let _ = client.abort_multipart_upload(b, root + "/abort.bin", second)
      let after = try {
        let _ = client.list_parts(b, root + "/abort.bin", second)
        "no-error"
      } catch {
        err =>
          match err {
            @error.CosError::Service(details) =>
              details.status.to_string() + " " + details.code
            _ => cos_text(err)
          }
      }
      println("放弃后查分片读数=" + after)
      assert_true(after.has_prefix("404"))
      assert_no_residue(client, root)
    }
  }
}

///|
async test "预签名 GET 免凭据可取、改签名即拒、窗口早过期即拒；PUT 直传真落盘" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let b = bucket()
      let root = prefix("presign")
      let key = root + "/signed-get.txt"
      let body = @utf8.encode("免凭据取回的那一份正文")
      let _ = client.put_object(b, key, body, content_type="text/plain")
      let url = client.presigned_get_url(b, key, expires_sec=600L)
      assert_true(url.find("q-sign-algorithm=sha1") is Some(_))
      let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
      let (status, got) = fetch_without_credentials(
        transport,
        @transport.Method::Get,
        url,
      )
      println(
        "免凭据 GET status=" +
        status.to_string() +
        " bytes=" +
        got.length().to_string(),
      )
      assert_eq(status, 200)
      assert_eq(got.to_array(), body.to_array())

      let (t_status, _) = fetch_without_credentials(
        transport,
        @transport.Method::Get,
        flip_signature(url),
      )
      println("改签名摘要位 status=" + t_status.to_string())
      assert_eq(t_status, 403)

      // 过期档不能靠"改 URL"来造——改一下就变成签名不符了。这里用**一个早已过去的窗口**
      // 现签一条，签名本身成立、窗口失效。参照实现文档明说"结束时间要大于起始时间，
      // 否则签名马上过期"，所以 403 就是这一档的读数。
      let stale = @auth.window_at(1000000000000L, 60L)
      let expired_url = client.config.url_of(b, key) +
        "?" +
        @auth.presign_query(
          client.config.credentials(),
          @auth.RequestToSign::{
            verb: "GET",
            path: @config.path_of(key),
            query: [],
            headers: [("host", client.config.host(b))],
          },
          stale,
        )
      let (e_status, e_body) = fetch_without_credentials(
        transport,
        @transport.Method::Get,
        expired_url,
      )
      let note = @utf8.decode_lossy(e_body.exact_view())
      println(
        "窗口过期读数：status=" +
        e_status.to_string() +
        " 正文含 expired=" +
        (note.find("expired") is Some(_)).to_string(),
      )
      assert_eq(e_status, 403)

      let put_url = client.presigned_put_url(
        b,
        root + "/direct-put.txt",
        expires_sec=600L,
      )
      let (p_status, _) = fetch_without_credentials(
        transport,
        @transport.Method::Put,
        put_url,
        body~,
      )
      println("预签名 PUT status=" + p_status.to_string())
      assert_eq(p_status, 200)
      let stat = client.stat_object(b, root + "/direct-put.txt")
      assert_eq(stat.size, body.length().to_int64())
      let _ = client.delete_object(b, key)
      let _ = client.delete_object(b, root + "/direct-put.txt")
      assert_no_residue(client, root)
    }
  }
}

///|
async test "原生 ACL 读写：写公有读真生效，改回私有匿名即拒" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let b = bucket()
      let root = prefix("acl")
      let key = root + "/acl.txt"
      let body = @utf8.encode("这一份要匿名取回")
      let _ = client.put_object(b, key, body)

      let initial = client.get_object_acl(b, key)
      println(
        "对象初始 ACL 读数：permissions=" +
        initial.permissions.join(",") +
        " public_read=" +
        initial.public_read.to_string(),
      )
      assert_true(!initial.public_read)

      let _ = client.put_object_acl(b, key, @cos.CannedAcl::PublicRead)
      let opened = client.get_object_acl(b, key)
      println(
        "写 public-read 之后：permissions=" +
        opened.permissions.join(",") +
        " public_read=" +
        opened.public_read.to_string(),
      )
      assert_true(opened.public_read)

      let url = client.presigned_get_url(b, key, expires_sec=60L)
      let bare = match url.find("?") {
        None => url
        Some(at) => url[0:at].to_owned()
      }
      let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
      let (anon_status, anon_body) = fetch_without_credentials(
        transport,
        @transport.Method::Get,
        bare,
      )
      println("匿名取回 status=" + anon_status.to_string())
      assert_eq(anon_status, 200)
      assert_eq(anon_body.to_array(), body.to_array())

      let _ = client.put_object_acl(b, key, @cos.CannedAcl::Private)
      let (back_status, _) = fetch_without_credentials(
        transport,
        @transport.Method::Get,
        bare,
      )
      println("改回 private 之后匿名 status=" + back_status.to_string())
      assert_eq(back_status, 403)

      // M10：对象级写 `public-read-write` 收不收。官方 PUT Object 的对象预设只列了
      // default／private／public-read，而 Go 那份枚举是并集（把桶级的档位也列进去了）——
      // 文档没写死的那一档只能实测。两臂都要断得住：收下就断它真给了至少两档授权，
      // 拒下就记下状态码，绝不留成一条不判的 println。
      let wide = try {
        let _ = client.put_object_acl(b, key, @cos.CannedAcl::PublicReadWrite)
        "accepted"
      } catch {
        @error.CosError::Service(details) =>
          "refused:" + details.status.to_string() + " " + details.code
        err => "other:" + cos_text(err)
      }
      println("M10 对象级 public-read-write 读数=" + wide)
      if wide == "accepted" {
        let widened = client.get_object_acl(b, key)
        println("写后 permissions=" + widened.permissions.join(","))
        assert_true(widened.permissions.length() >= 2)
      } else if !wide.has_prefix("refused:") {
        fail("M10 的读数落在两臂之外：" + wide)
      }
      let _ = client.delete_object(b, key)
      assert_no_residue(client, root)
    }
  }
}

///|
/// 换错密钥的那一发：整条签名面唯一"服务端认不认这把钥匙"的负判据。
/// 从真 SK 改一个字符得到，值本身从不打印，只打印状态码与 Code。
async test "错密钥必须被拒，且拒在签名上而不是别处" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let chars = environment.1.to_array()
      let last = chars.length() - 1
      let flipped = if chars[last] == 'a' { "b" } else { "a" }
      let wrong_sk = environment.1[0:last].to_owned() +
        flipped +
        environment.1[last + 1:chars.length()].to_owned()
      let client = build(environment.0, wrong_sk, region())
      let note = try {
        let _ = client.put_object(
          bucket(),
          prefix("wrongskey") + "/never.txt",
          @utf8.encode("不该落盘"),
        )
        "no-error"
      } catch {
        @error.CosError::Service(details) =>
          "status=" + details.status.to_string() + " code=<" + details.code + ">"
        err => cos_text(err)
      }
      println("错密钥读数=" + note)
      assert_true(note.has_prefix("status=403"))
      assert_true(!note.has_prefix("status=403 code=<>"))
    }
  }
}

///|
async test "服务级列举与错区域的读数（M12）" {
  match live_env() {
    None => skip_note()
    Some(environment) => {
      let client = build(environment.0, environment.1, region())
      let buckets = client.list_buckets()
      println("服务级列举条数=" + buckets.length().to_string())
      assert_true(buckets.length() >= 1)
      let name = bucket()
      assert_true(buckets.any(item => item.name == name))

      // M12：签名里**没有**区域，错区域只会错在 host 上。所以这一发的读数不是
      // "签名不符"，而是能不能连上、回了什么码——按实测记录，不预设。
      let wrong = build(environment.0, environment.1, "ap-beijing")
      let note = try {
        let _ = wrong.stat_object(name, "moonfs-cos-absent.bin")
        "no-error（那个 host 也应答，判据要改）"
      } catch {
        err =>
          match err {
            @error.CosError::Service(details) =>
              "status=" +
              details.status.to_string() +
              " code=<" +
              details.code +
              ">"
            _ => cos_text(err)
          }
      }
      println("M12 错区域读数=" + note)
      assert_true(!note.has_prefix("no-error"))
    }
  }
}

///|

///|
/// 自己写的自己删干净：这一档非 0 就是往真桶里漏了东西（与七牛、OSS 那条腿同一纪律）。
async fn assert_no_residue(client : @cos.Client, root : String) -> Unit {
  let listing = client.list_objects(bucket(), prefix=root)
  if listing.objects.length() != 0 {
    let left : Array[String] = []
    for item in listing.objects {
      left.push(item.key)
    }
    fail("residue under " + root + ": " + left.join(", "))
  }
}

///|
/// 改**签名本体**的一个字符。跳过尾部的 `0`（hex 里那几位改成 `a` 也能过校验的
/// 概率极低，但要避开的是"改了个没用的位"这种假绿），参照 moon-kodo 那条腿的同款纪律。
fn flip_signature(url : String) -> String raise {
  let chars = url.to_array()
  let at = match url.find("q-signature=") {
    None => fail("no q-signature in the presigned url")
    Some(at) => at + "q-signature=".length()
  }
  let mut pos = chars.length() - 1
  while pos > at && chars[pos] == '0' {
    pos = pos - 1
  }
  if pos <= at {
    fail("q-signature has nothing to flip")
  }
  let after = if chars[pos] == 'a' { "b" } else { "a" }
  url[0:pos].to_owned() + after + url[pos + 1:chars.length()].to_owned()
}
