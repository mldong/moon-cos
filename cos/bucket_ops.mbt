///|
/// 桶族：服务级列举桶、桶内列举。COS 原生**没有 ListObjectsV2**（文档的参数表里没有
/// `list-type`，三份参照实现全文都搜不到它），所以翻页游标只有 `marker`／`NextMarker`
/// 这一对。兼容层那一侧能不能用 V2 是另一档（实测 M7），本模块不代它承诺。

///|
pub(all) struct BucketInfo {
  name : String
  /// 形如 `ap-guangzhou`，是桶真正在的那个区
  location : String
  creation_date : String
}

///|
/// 服务级列举：走 `service.cos.myqcloud.com`，host 里没有桶名（参照实现同形）。
/// 这一发的签名里 path 是 `/`、参数为空——它顺带证明了"根路径也能签对"这件事。
pub async fn Client::list_buckets(
  self : Client,
) -> Array[BucketInfo] raise @error.CosError {
  let response = request(self, "GET", bucket="", key="")
  let body = response_body_text(response.body, response.status)
  let out : Array[BucketInfo] = []
  for section in xml_sections(body, "Bucket") {
    out.push(BucketInfo::{
      name: or_empty(xml_first(section, "Name")),
      location: or_empty(xml_first(section, "Location")),
      creation_date: or_empty(xml_first(section, "CreationDate")),
    })
  }
  out
}

///|
/// 桶内列举。**始终带 `encoding-type=url`**：回包里的 `Key`／`CommonPrefixes><Prefix>`／
/// `NextMarker` 因此是一次 URL 编码的形态，本函数把它解回来后再交给调用方，
/// 两侧坐标系与 `put_object` 的 `key` 一致。
///
/// 选这一档而不是"读 XML 实体"的理由很实在：键里允许出现 `&`／`<`／实体写法本身，
/// 走实体就要面对"容器段解一趟、叶子上再解一趟"的二次解码问题（隔壁 `moon-s3` 真栽过一次，
/// 修法是容器切段不解转义）。带 `encoding-type=url` 之后，那一路整段不存在——
/// 解码只有一次，而且解的是百分号而不是实体。
pub async fn Client::list_objects(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  delimiter~ : String = "",
  marker~ : String = "",
  max_keys~ : Int32 = 0,
) -> ObjectListing raise @error.CosError {
  let query : Array[(String, String)] = [("encoding-type", "url")]
  if !prefix.is_empty() {
    query.push(("prefix", prefix))
  }
  if !delimiter.is_empty() {
    query.push(("delimiter", delimiter))
  }
  if !marker.is_empty() {
    query.push(("marker", marker))
  }
  if max_keys > 0 {
    query.push(("max-keys", max_keys.to_string()))
  }
  let response = request(self, "GET", bucket~, key="", query~)
  let body = response_body_text(response.body, response.status)
  let objects : Array[ObjectInfo] = []
  for section in xml_sections(body, "Contents") {
    objects.push(ObjectInfo::{
      key: decode_listed(or_empty(xml_first(section, "Key"))),
      etag: xml_first(section, "ETag"),
      size: parse_int64(or_empty(xml_first(section, "Size"))),
      last_modified: xml_first(section, "LastModified"),
    })
  }
  let prefixes : Array[String] = []
  for section in xml_sections(body, "CommonPrefixes") {
    prefixes.push(decode_listed(or_empty(xml_first(section, "Prefix"))))
  }
  ObjectListing::{
    objects,
    common_prefixes: prefixes,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_marker: match xml_first(body, "NextMarker") {
      None => None
      Some(value) => Some(decode_listed(value))
    },
    encoding_type: xml_first(body, "EncodingType"),
    body,
  }
}

///|
/// 回包里的编码态读数解回来。用了 `decode_lossy` 而不是 `decode`：这一档失败的含义是
/// "服务端给的形态与我们的请求不一致"，那是读数问题而不是传输问题，
/// 把它升成 `raise` 会让一次列举整页丢掉；解不动就原样保留，`body` 那一格随时可回查。
fn decode_listed(text : String) -> String {
  if text.find("%") is None {
    text
  } else {
    @percent.decode_lossy(text.view())
  }
}

///|
fn parse_int64(text : String) -> Int64 {
  @string.parse_int64(text.view(), base=10) catch {
    _ => 0L
  }
}
