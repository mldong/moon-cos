///|
/// 分片族五步加一页读数。COS 的参数名是驼峰的 `partNumber`／`uploadId`，
/// 而**签名串里它们是小写键**（参照实现先编码再整体小写）——两处不同形是协议定义，
/// 签名件那侧的向量档钉着这一条，这里只负责发的时候保留原样。
///
/// 每片 1 MB–5 GB、最多 10000 片、最后一片可以小于 1 MB；过小回 400 `EntityTooSmall`。
/// 这条下限与 AWS 的 5 MB 不同（更宽），所以文件存储契约里 5 MiB 那一档天然满足，
/// 不需要为 COS 改正文。

///|
pub(all) struct PartInfo {
  part_number : Int32
  etag : String
  size : Int64
  last_modified : String?
}

///|
pub(all) struct PartPage {
  parts : Array[PartInfo]
  is_truncated : Bool
  next_part_number_marker : String?
}

///|
pub(all) struct CompleteResult {
  etag : String
  body : String
}

///|
/// 第一步：开一个分片会话。对象名在这一发就定下来了，元数据与 ACL 也在这时给
/// （后面每片只带数据，不再改这些）。
pub async fn Client::create_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  content_type~ : String = "",
  metadata~ : Array[(String, String)] = [],
  acl~ : CannedAcl = Private,
  set_acl~ : Bool = false,
) -> String raise @error.CosError {
  let response = request(
    self,
    "POST",
    bucket~,
    key~,
    headers=object_headers(content_type~, metadata~, acl~, set_acl~),
    query=[("uploads", "")],
  )
  let body = response_body_text(response.body, response.status)
  match xml_first(body, "UploadId") {
    None =>
      raise @error.BadResponse(
        "no UploadId in the initiate response, status " +
        response.status.to_string(),
      )
    Some(upload_id) => upload_id
  }
}

///|
/// 一片。返回的是这一片的 ETag（**带引号原样**，本模块不剥）：完成件要把同一串写回
/// `CompleteMultipartUpload`，剥了引号就得再拼回去，两处各改一次是错的来源。
pub async fn Client::upload_part(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
  part_number : Int32,
  data : Bytes,
) -> String raise @error.CosError {
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    query=[("partNumber", part_number.to_string()), ("uploadId", upload_id)],
    body=@transport.RequestBody::Bytes(data),
  )
  discard_body(response)
  match header_of(response.headers, "etag") {
    None => raise @error.BadResponse("no ETag header on a completed part")
    Some(etag) => etag
  }
}

///|
pub async fn Client::list_parts(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> PartPage raise @error.CosError {
  let response = request(self, "GET", bucket~, key~, query=[
    ("uploadId", upload_id),
  ])
  let body = response_body_text(response.body, response.status)
  let parts : Array[PartInfo] = []
  for section in xml_sections(body, "Part") {
    parts.push(PartInfo::{
      part_number: parse_int32(or_empty(xml_first(section, "PartNumber"))),
      etag: or_empty(xml_first(section, "ETag")),
      size: parse_int64(or_empty(xml_first(section, "Size"))),
      last_modified: xml_first(section, "LastModified"),
    })
  }
  PartPage::{
    parts,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_part_number_marker: xml_first(body, "NextPartNumberMarker"),
  }
}

///|
/// 完成。`parts` 必须**按片号升序**——COS 对乱序回 400 `InvalidPartOrder`，
/// 本函数不替你排序（排序一次就多一处与调用方手里那份清单不一致的地方）。
///
/// 完成件的 ETag 带 `-N` 后缀（文档示例给的是 `…-3`），它不是整份对象的 MD5；
/// 本模块原样带回，不剥后缀、不拿它当校验依据。
pub async fn Client::complete_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
  parts~ : Array[(Int32, String)],
) -> CompleteResult raise @error.CosError {
  let document = complete_document(parts)
  let response = request(
    self,
    "POST",
    bucket~,
    key~,
    headers=[("content-type", "application/xml")],
    query=[("uploadId", upload_id)],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  let body = response_body_text(response.body, response.status)
  CompleteResult::{ etag: or_empty(xml_first(body, "ETag")), body, }
}

///|
pub async fn Client::abort_multipart_upload(
  self : Client,
  bucket : String,
  key : String,
  upload_id : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, key~, query=[
    ("uploadId", upload_id),
  ])
  discard_body(response)
}

///|
fn complete_document(parts : Array[(Int32, String)]) -> String {
  let mut out = "<CompleteMultipartUpload>"
  for pair in parts {
    let number = pair.0.to_string()
    let quoted = xml_escape(pair.1)
    out = out +
      "<Part><PartNumber>" +
      number +
      "</PartNumber><ETag>" +
      quoted +
      "</ETag></Part>"
  }
  out + "</CompleteMultipartUpload>"
}

///|
fn parse_int32(text : String) -> Int32 {
  @string.parse_int(text.view(), base=10) catch {
    _ => 0
  }
}
