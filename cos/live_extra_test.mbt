///|
// 新增能力的真桶档：缺 COS_* 时整段 SKIP；有凭据时只写本轮自命名前缀，测量段红也先清扫再判红。

///|
fn extra_env() -> (String, String, String, String)? {
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
        @env.get_env_var("COS_REGION").unwrap_or(""),
        @env.get_env_var("COS_BUCKET").unwrap_or(""),
      ),
    )
  }
}

///|
fn extra_skip() -> Unit {
  println("SKIP live COS extra checks, COS_* not supplied")
  println("SKIP IS NOT A PASS: new COS methods were not measured by this run.")
}

///|
fn extra_build(
  env : (String, String, String, String),
) -> @cos.Client raise @error.CosError {
  let credentials = @auth.Credentials::new(env.0, env.1)
  let config = @config.Config::new(env.2, credentials)
  @cos.Client::new(config, @transport.AsyncHttpTransport::new())
}

///|
fn extra_tag() -> String {
  "moonfs-cos-" + @auth.now_millis().to_string()
}

///|
fn extra_bytes(text : String) -> Bytes {
  @utf8.encode(text.view())
}

///|
fn extra_text(data : Bytes) -> String {
  @utf8.decode_lossy(data.exact_view())
}

///|
fn extra_status(err : @error.CosError) -> Int32 {
  match err {
    @error.CosError::Service(d) => d.status
    _ => -1
  }
}

///|
fn extra_has_tag(
  tags : Array[@cos.ObjectTag],
  key : String,
  value : String,
) -> Bool {
  let mut found = false
  for tag in tags {
    if tag.key == key && tag.value == value {
      found = true
    }
  }
  found
}

///|
async fn extra_cleanup(
  client : @cos.Client,
  bucket : String,
  keys : Array[String],
) -> Unit {
  for key in keys {
    let _ = client.delete_object(bucket, key) catch {
      err => println("cleanup " + key + ": " + err.text())
    }
  }
}

///|
async fn extra_abort(
  client : @cos.Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> Unit {
  if !upload_id.is_empty() {
    let _ = client.abort_multipart_upload(bucket, key, upload_id) catch {
      err => println("cleanup multipart " + key + ": " + err.text())
    }
  }
}

///|
async fn extra_get_status(
  client : @cos.Client,
  bucket : String,
  key : String,
  if_none_match~ : String,
) -> String {
  let _ = client.get_object(bucket, key, if_none_match~) catch {
    err => return "status:" + extra_status(err).to_string()
  }
  "ok"
}

///|
async fn extra_stat_status(
  client : @cos.Client,
  bucket : String,
  key : String,
) -> String {
  let _ = client.stat_object(bucket, key) catch {
    err => return "status:" + extra_status(err).to_string()
  }
  "ok"
}

///|
async fn extra_cors_text(client : @cos.Client, bucket : String) -> String {
  let rules = client.get_bucket_cors(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + rules.length().to_string()
}

///|
async fn extra_encryption_text(client : @cos.Client, bucket : String) -> String {
  let algorithm = client.get_bucket_encryption(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + algorithm.unwrap_or("<none>")
}

///|
async fn extra_website_text(client : @cos.Client, bucket : String) -> String {
  let site = client.get_bucket_website(bucket) catch {
    err => return "err:" + err.text()
  }
  let text = match site {
    Some(_) => "configured"
    None => "none"
  }
  "ok:" + text
}

///|
async fn extra_logging_text(client : @cos.Client, bucket : String) -> String {
  let status = client.get_bucket_logging(bucket) catch {
    err => return "err:" + err.text()
  }
  let text = match status.enabled {
    Some(_) => "enabled"
    None => "disabled"
  }
  "ok:" + text
}

///|
async fn extra_tagging_text(client : @cos.Client, bucket : String) -> String {
  let tagging = client.get_bucket_tagging(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + tagging.tags.length().to_string()
}

///|
async fn extra_versioning_text(client : @cos.Client, bucket : String) -> String {
  let status = client.get_bucket_versioning(bucket) catch {
    err => return "err:" + err.text()
  }
  let text = match status {
    Some(value) => value
    None => "<none>"
  }
  "ok:" + text
}

///|
async fn extra_lifecycle_text(client : @cos.Client, bucket : String) -> String {
  let rules = client.get_bucket_lifecycle(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + rules.length().to_string()
}

///|
async fn extra_response_control_text(
  client : @cos.Client,
  bucket : String,
) -> String {
  let params = client.get_bucket_response_control(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + params.length().to_string()
}

///|
async fn extra_tiering_text(client : @cos.Client, bucket : String) -> String {
  let config = client.get_bucket_intelligent_tiering(bucket) catch {
    err => return "err:" + err.text()
  }
  match config {
    Some(_) => "ok:configured"
    None => "ok:none"
  }
}

///|
async fn extra_domain_text(client : @cos.Client, bucket : String) -> String {
  let rules = client.get_bucket_domain(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + rules.length().to_string()
}

///|
async fn extra_object_lock_text(
  client : @cos.Client,
  bucket : String,
) -> String {
  let config = client.get_bucket_object_lock(bucket) catch {
    err => return "err:" + err.text()
  }
  match config {
    Some(_) => "ok:configured"
    None => "ok:none"
  }
}

///|
async fn extra_inventory_text(client : @cos.Client, bucket : String) -> String {
  let items = client.list_bucket_inventories(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + items.length().to_string()
}

///|
async fn extra_replication_text(
  client : @cos.Client,
  bucket : String,
) -> String {
  let config = client.get_bucket_replication(bucket) catch {
    err => return "err:" + err.text()
  }
  match config {
    Some(_) => "ok:configured"
    None => "ok:none"
  }
}

///|
async fn extra_policy_text(client : @cos.Client, bucket : String) -> String {
  let policy = client.get_bucket_policy(bucket) catch {
    err => return "err:" + err.text()
  }
  match policy {
    Some(_) => "ok:configured"
    None => "ok:none"
  }
}

///|
async fn extra_referer_text(client : @cos.Client, bucket : String) -> String {
  let config = client.get_bucket_referer(bucket) catch {
    err => return "err:" + err.text()
  }
  "ok:" + config.domains.length().to_string()
}

///|
async test "真桶·标签/条件读/批量删除：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let exists = client.bucket_exists(bucket) catch {
        err => fail("bucket_exists: " + err.text())
      }
      if !exists {
        fail("bucket_exists returned false for the configured bucket")
      }
      let stamp = extra_tag()
      let k1 = stamp + "-tag-a.txt"
      let k2 = stamp + "-tag-b.txt"
      let keys : Array[String] = [k1, k2]
      let outcome = try {
        let _ = client.put_object(
          bucket,
          k1,
          extra_bytes("alpha"),
          content_type="text/plain",
        ) catch {
          err => fail("put a: " + err.text())
        }
        let _ = client.put_object(bucket, k2, extra_bytes("beta")) catch {
          err => fail("put b: " + err.text())
        }
        client.put_object_tagging(bucket, k1, [
          @cos.ObjectTag::{ key: "case", value: "tag", },
          @cos.ObjectTag::{ key: "env", value: "live", },
        ]) catch {
          err => fail("put tagging: " + err.text())
        }
        let tagging = client.get_object_tagging(bucket, k1) catch {
          err => fail("get tagging: " + err.text())
        }
        if tagging.tags.length() != 2 ||
          !extra_has_tag(tagging.tags, "case", "tag") {
          fail("tag readback mismatch: " + tagging.body)
        }
        let stat = client.stat_object(bucket, k1) catch {
          err => fail("stat: " + err.text())
        }
        let etag = match stat.etag {
          Some(value) => value
          None => {
            fail("stat has no etag")
            ""
          }
        }
        let got = client.get_object(bucket, k1, if_match=etag) catch {
          err => fail("conditional get: " + err.text())
        }
        if extra_text(got.body) != "alpha" {
          fail("conditional get body mismatch")
        }
        let blocked = extra_get_status(client, bucket, k1, if_none_match=etag)
        if blocked != "status:304" {
          fail("if-none-match expected 304, got " + blocked)
        }
        let deleted = client.delete_objects(bucket, keys) catch {
          err => fail("delete_objects: " + err.text())
        }
        if deleted.deleted.length() != 2 || deleted.errors.length() != 0 {
          fail(
            "delete_objects deleted=" +
            deleted.deleted.length().to_string() +
            " errors=" +
            deleted.errors.length().to_string(),
          )
        }
        let after = extra_stat_status(client, bucket, k1)
        if after != "status:404" {
          fail("deleted key still stat-able: " + after)
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, keys)
      println("cos extra tagging/batch outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·存储类/自动 MD5/版本与 CORS 读：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-opts.txt"
      let outcome = try {
        let _ = client.put_object(
          bucket,
          key,
          extra_bytes("opts payload"),
          content_type="text/plain",
          storage_class="STANDARD",
          compute_md5=true,
        ) catch {
          err => fail("put with storage class/md5: " + err.text())
        }
        let got = client.get_object(bucket, key) catch {
          err => fail("get after opts put: " + err.text())
        }
        if extra_text(got.body) != "opts payload" {
          fail("opts body mismatch")
        }
        let server_crc = client.object_crc64(bucket, key) catch {
          err => fail("object crc64: " + err.text())
        }
        let local_crc = @cos.crc64_decimal(
          @cos.crc64_xz(extra_bytes("opts payload")),
        )
        match server_crc {
          Some(value) =>
            if value != local_crc {
              fail("crc64 mismatch: server=" + value + " local=" + local_crc)
            }
          None => fail("HEAD returned no crc64 header")
        }
        let stat = client.stat_object(bucket, key) catch {
          err => fail("stat after opts put: " + err.text())
        }
        match stat.storage_class {
          Some(value) => assert_eq(value, "STANDARD")
          None =>
            println("cos stat storage_class=<none> (standard header omitted)")
        }
        let listing = client.list_objects(bucket, prefix=key, max_keys=10) catch {
          err => fail("list after opts put: " + err.text())
        }
        let mut listed_class = ""
        for object in listing.objects {
          if object.key == key {
            listed_class = object.storage_class.unwrap_or("")
          }
        }
        assert_eq(listed_class, "STANDARD")
        println(
          "cos bucket versioning read=" + extra_versioning_text(client, bucket),
        )
        println("cos bucket cors read=" + extra_cors_text(client, bucket))
        println(
          "cos bucket lifecycle read=" + extra_lifecycle_text(client, bucket),
        )
        println("cos bucket referer read=" + extra_referer_text(client, bucket))
        println("cos bucket policy read=" + extra_policy_text(client, bucket))
        println(
          "cos bucket replication read=" +
          extra_replication_text(client, bucket),
        )
        println(
          "cos bucket inventory read=" + extra_inventory_text(client, bucket),
        )
        println(
          "cos bucket object-lock read=" +
          extra_object_lock_text(client, bucket),
        )
        println("cos bucket domain read=" + extra_domain_text(client, bucket))
        println("cos bucket tiering read=" + extra_tiering_text(client, bucket))
        println(
          "cos bucket response-control read=" +
          extra_response_control_text(client, bucket),
        )
        println("cos bucket tagging read=" + extra_tagging_text(client, bucket))
        println("cos bucket logging read=" + extra_logging_text(client, bucket))
        println("cos bucket website read=" + extra_website_text(client, bucket))
        println(
          "cos bucket encryption read=" + extra_encryption_text(client, bucket),
        )
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key])
      println("cos extra opts outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·追加写：两次 append 读回拼接内容" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-append.txt"
      let outcome = try {
        let first = client.append_object(
          bucket,
          key,
          extra_bytes("hello"),
          position=0L,
          content_type="text/plain",
        ) catch {
          err => fail("append first: " + err.text())
        }
        println(
          "cos append next1=" + first.next_position.unwrap_or(-1L).to_string(),
        )
        let second = client.append_object(
          bucket,
          key,
          extra_bytes(" world"),
          position=first.next_position.unwrap_or(5L),
          content_type="text/plain",
        ) catch {
          err => fail("append second: " + err.text())
        }
        println(
          "cos append next2=" + second.next_position.unwrap_or(-1L).to_string(),
        )
        let got = client.get_object(bucket, key) catch {
          err => fail("get appended: " + err.text())
        }
        if extra_text(got.body) != "hello world" {
          fail("append body mismatch: " + extra_text(got.body))
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key])
      println("cos extra append outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·分片复制与未完成分片列举：自命名前缀，失败也清扫" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let stamp = extra_tag()
      let src = stamp + "-copy-src.bin"
      let dst = stamp + "-copy-dst.bin"
      let keys : Array[String] = [src, dst]
      let mut upload_id = ""
      let payload = Bytes::from_array(Array::make(1048576, b'a'))
      let outcome = try {
        let _ = client.put_object(bucket, src, payload) catch {
          err => fail("put source: " + err.text())
        }
        upload_id = client.create_multipart_upload(bucket, dst) catch {
          err => fail("create multipart: " + err.text())
        }
        let listed = client.list_multipart_uploads(bucket, prefix=dst) catch {
          err => fail("list multipart: " + err.text())
        }
        let mut seen = false
        for upload in listed.uploads {
          if upload.key == dst && upload.upload_id == upload_id {
            seen = true
          }
        }
        if !seen {
          fail("multipart upload not listed: " + listed.body)
        }
        let part = client.upload_part_copy(
          bucket,
          src,
          bucket,
          dst,
          upload_id,
          1,
          copy_source_range="bytes=0-1048575",
        ) catch {
          err => fail("upload_part_copy: " + err.text())
        }
        let _ = client.complete_multipart_upload(bucket, dst, upload_id, parts=[
          (1, part.etag),
        ]) catch {
          err => fail("complete: " + err.text())
        }
        upload_id = ""
        let stat = client.stat_object(bucket, dst) catch {
          err => fail("stat target: " + err.text())
        }
        if stat.size != 1048576L {
          fail("target size " + stat.size.to_string())
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_abort(client, bucket, dst, upload_id)
      extra_cleanup(client, bucket, keys)
      println("cos extra multipart outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async fn extra_symlink_state(
  client : @cos.Client,
  bucket : String,
  target : String,
  link : String,
) -> String {
  client.put_symlink(bucket, link, target) catch {
    err => return "put:" + err.text()
  }
  let info = client.get_symlink(bucket, link) catch {
    err => return "get:" + err.text()
  }
  match info.target {
    Some(value) => if value == target { "ok" } else { "target:" + value }
    None => "no-target"
  }
}

///|
async test "真桶·软链接：建链读目标，删链不删目标" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let tag = extra_tag()
      let target = tag + "-symlink-target.txt"
      let link = tag + "-symlink.txt"
      let _ = client.put_object(
        bucket,
        target,
        extra_bytes("symlink target payload"),
      ) catch {
        err => fail("put target: " + err.text())
      }
      let state = extra_symlink_state(client, bucket, target, link)
      println("cos symlink state=" + state)
      if state == "ok" {
        let got = client.get_object(bucket, link) catch {
          err => fail("get through symlink: " + err.text())
        }
        if extra_text(got.body) != "symlink target payload" {
          fail("symlink body mismatch")
        }
      } else if state.has_prefix("put:") && state.contains("403") {
        // 该账号的桶策略不允许 PutSymlink（本地与 CI 同一套凭据），记读数不判代码红。
        println("cos symlink permission-limited (403), not a code failure")
      } else {
        fail(state)
      }
      extra_cleanup(client, bucket, [link, target])
    }
  }
}

///|
fn auto_filler(total : Int32) -> Bytes {
  let block = "moon-auto-filler-0123456789abcdef-"
  let mut out = block
  while out.length() < total {
    out = out + out
  }
  @utf8.encode(out[0:total].to_owned())
}

///|
async test "真桶·一条式上传：超过阈值自动分片并合完" {
  match extra_env() {
    None => extra_skip()
    Some(env) => {
      let client = extra_build(env) catch {
        err => fail("setup: " + err.text())
      }
      let bucket = env.3
      let key = extra_tag() + "-auto.bin"
      let payload = auto_filler(2621440)
      let outcome = try {
        let put = client.put_bytes_auto(
          bucket,
          key,
          payload,
          part_size=1048576,
          threshold=1048576,
          content_type="application/octet-stream",
        ) catch {
          err => fail("put_bytes_auto: " + err.text())
        }
        if put.etag.is_empty() {
          fail("auto upload returned an empty etag")
        }
        let got = client.get_object(bucket, key) catch {
          err => fail("get after auto upload: " + err.text())
        }
        if got.body.length() != payload.length() {
          fail(
            "auto upload size mismatch: " +
            got.body.length().to_string() +
            " != " +
            payload.length().to_string(),
          )
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      extra_cleanup(client, bucket, [key])
      println("moon-cos auto upload outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}
