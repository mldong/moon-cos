///|
/// 分片复制与未完成分片列举。两者复用现有 `request` 链与 XML 读取件。

///|
/// `PUT /<key>?partNumber=N&uploadId=...`，数据从源对象按范围复制。
/// `copy_source_range~` 收 HTTP Range 原值（如 `bytes=0-1023`），SDK 不翻译。
pub async fn Client::upload_part_copy(
  self : Client,
  source_bucket : String,
  source_key : String,
  bucket : String,
  key : String,
  upload_id : String,
  part_number : Int32,
  copy_source_range~ : String = "",
  copy_source_if_match~ : String = "",
  copy_source_if_none_match~ : String = "",
  copy_source_if_modified_since~ : String = "",
  copy_source_if_unmodified_since~ : String = "",
) -> UploadPartCopyResult raise @error.CosError {
  check_part_number(part_number)
  if upload_id.is_empty() {
    raise @error.BadParam("upload id is required")
  }
  let conditions = copy_source_conditional_headers(
    if_match=copy_source_if_match,
    if_none_match=copy_source_if_none_match,
    if_modified_since=copy_source_if_modified_since,
    if_unmodified_since=copy_source_if_unmodified_since,
  )
  let headers : Array[(String, String)] = [
    (
      "x-cos-copy-source",
      self.config.canonical_host(source_bucket) +
      "/" +
      @config.encode_key(source_key),
    ),
  ]
  if !copy_source_range.is_empty() {
    headers.push(("x-cos-copy-source-range", copy_source_range))
  }
  headers.append(conditions)
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    query=[("partNumber", part_number.to_string()), ("uploadId", upload_id)],
    headers~,
  )
  let body = response_body_text(response.body, response.status)
  parse_upload_part_copy_result(body, response.headers)
}

///|
/// `GET /?uploads`：列未完成分片任务。按 `<Upload>` 切段，避免两列错配。
pub async fn Client::list_multipart_uploads(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  delimiter~ : String = "",
  max_uploads~ : Int32 = 1000,
  key_marker~ : String = "",
  upload_id_marker~ : String = "",
) -> MultipartUploadListing raise @error.CosError {
  if max_uploads < 1 || max_uploads > 1000 {
    raise @error.BadParam(
      "max_uploads must be within 1..1000, got " + max_uploads.to_string(),
    )
  }
  let query = multipart_uploads_query(
    prefix~,
    delimiter~,
    max_uploads~,
    key_marker~,
    upload_id_marker~,
  )
  let response = request(self, "GET", bucket~, key="", query~)
  let body = response_body_text(response.body, response.status)
  parse_multipart_upload_listing(body)
}

///|
fn check_part_number(part_number : Int32) -> Unit raise @error.CosError {
  if part_number < 1 || part_number > 10000 {
    raise @error.BadParam(
      "part number must be within 1..10000, got " + part_number.to_string(),
    )
  }
}

///|
fn multipart_uploads_query(
  prefix~ : String,
  delimiter~ : String,
  max_uploads~ : Int32,
  key_marker~ : String,
  upload_id_marker~ : String,
) -> Array[(String, String)] {
  let query : Array[(String, String)] = [
    ("uploads", ""),
    ("max-uploads", max_uploads.to_string()),
  ]
  add_param(query, "prefix", prefix)
  add_param(query, "delimiter", delimiter)
  add_param(query, "key-marker", key_marker)
  add_param(query, "upload-id-marker", upload_id_marker)
  query
}

///|
fn add_param(
  query : Array[(String, String)],
  name : String,
  value : String,
) -> Unit {
  if !value.is_empty() {
    query.push((name, value))
  }
}

///|
fn parse_upload_part_copy_result(
  body : String,
  headers : Array[@transport.Header],
) -> UploadPartCopyResult {
  let xml_etag = or_empty(xml_first(body, "ETag"))
  let etag = if xml_etag.is_empty() {
    or_empty(header_of(headers, "etag"))
  } else {
    xml_etag
  }
  UploadPartCopyResult::{
    etag,
    last_modified: xml_first(body, "LastModified"),
    body,
  }
}

///|
fn parse_multipart_upload_listing(body : String) -> MultipartUploadListing {
  let uploads : Array[MultipartUploadInfo] = []
  for section in xml_sections(body, "Upload") {
    uploads.push(MultipartUploadInfo::{
      key: or_empty(xml_first(section, "Key")),
      upload_id: or_empty(xml_first(section, "UploadId")),
      initiated: xml_first(section, "Initiated"),
    })
  }
  let prefixes : Array[String] = []
  for group in xml_sections(body, "CommonPrefixes") {
    prefixes.push(or_empty(xml_first(group, "Prefix")))
  }
  MultipartUploadListing::{
    uploads,
    common_prefixes: prefixes,
    is_truncated: or_empty(xml_first(body, "IsTruncated")) == "true",
    next_key_marker: nonempty(xml_first(body, "NextKeyMarker")),
    next_upload_id_marker: nonempty(xml_first(body, "NextUploadIdMarker")),
    body,
  }
}

///|
fn nonempty(value : String?) -> String? {
  match value {
    Some(text) => if text.is_empty() { None } else { Some(text) }
    None => None
  }
}
