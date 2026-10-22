///|
/// 批量删除。COS 的 `DeleteMultipleObjects` 走 `POST /?delete`，请求体是 XML，
/// `Content-MD5` 是必带头。上限按官方文档在本地先拒（1000 个键）。
pub async fn Client::delete_objects(
  self : Client,
  bucket : String,
  keys : Array[String],
  quiet~ : Bool = false,
) -> DeleteObjectsResult raise @error.CosError {
  if keys.is_empty() {
    raise @error.BadParam("delete_objects needs at least one key")
  }
  if keys.length() > 1000 {
    raise @error.BadParam(
      "delete_objects accepts at most 1000 keys per request, got " +
      keys.length().to_string(),
    )
  }
  for key in keys {
    if key.is_empty() {
      raise @error.BadParam("delete_objects key must not be empty")
    }
  }
  let document = delete_objects_document(keys, quiet)
  let body = @utf8.encode(document.view())
  let content_md5 = delete_objects_content_md5(body)
  let response = request(
    self,
    "POST",
    bucket~,
    query=[("delete", "")],
    headers=[("content-type", "application/xml"), ("content-md5", content_md5)],
    body=@transport.RequestBody::Bytes(body),
  )
  let text = response_body_text(response.body, response.status)
  parse_delete_objects_result(text)
}

///|
fn delete_objects_document(keys : Array[String], quiet : Bool) -> String {
  let mut out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Delete>"
  if quiet {
    out = out + "<Quiet>true</Quiet>"
  }
  for key in keys {
    out = out + "<Object><Key>" + xml_escape(key) + "</Key></Object>"
  }
  out + "</Delete>"
}

///|
fn delete_objects_content_md5(body : Bytes) -> String {
  @base64.encode(@digest.md5_of_bytes(body).exact_view())
}

///|
fn parse_delete_objects_result(body : String) -> DeleteObjectsResult {
  let deleted : Array[String] = []
  for section in xml_sections(body, "Deleted") {
    match xml_first(section, "Key") {
      Some(key) => deleted.push(key)
      None => ()
    }
  }
  let errors : Array[DeleteObjectFailure] = []
  for section in xml_sections(body, "Error") {
    errors.push(DeleteObjectFailure::{
      key: or_empty(xml_first(section, "Key")),
      code: or_empty(xml_first(section, "Code")),
      message: or_empty(xml_first(section, "Message")),
    })
  }
  DeleteObjectsResult::{ deleted, errors, body, }
}
