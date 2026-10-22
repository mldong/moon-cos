///|
/// 对象标签三件：写、读、删。三者共用 `?tagging` 子资源与 XML 正文。

///|
pub async fn Client::put_object_tagging(
  self : Client,
  bucket : String,
  key : String,
  tags : Array[ObjectTag],
) -> Unit raise @error.CosError {
  check_tags(tags)
  let document = tagging_document(tags)
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    query=[("tagging", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_object_tagging(
  self : Client,
  bucket : String,
  key : String,
) -> ObjectTagging raise @error.CosError {
  let response = request(self, "GET", bucket~, key~, query=[("tagging", "")])
  let body = response_body_text(response.body, response.status)
  parse_object_tagging(body)
}

///|
pub async fn Client::delete_object_tagging(
  self : Client,
  bucket : String,
  key : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, key~, query=[("tagging", "")])
  discard_body(response)
}

///|
fn check_tags(tags : Array[ObjectTag]) -> Unit raise @error.CosError {
  if tags.is_empty() {
    raise @error.BadParam("put_object_tagging needs at least one tag")
  }
  if tags.length() > 10 {
    raise @error.BadParam(
      "put_object_tagging accepts at most 10 tags, got " +
      tags.length().to_string(),
    )
  }
  for i in 0..<tags.length() {
    let tag = tags[i]
    if tag.key.is_empty() {
      raise @error.BadParam("object tag key must not be empty")
    }
    if tag.key.length() > 128 {
      raise @error.BadParam("object tag key exceeds 128 characters")
    }
    if tag.value.length() > 256 {
      raise @error.BadParam("object tag value exceeds 256 characters")
    }
    for j in (i + 1)..<tags.length() {
      if tag.key == tags[j].key {
        raise @error.BadParam("object tag keys must be unique: " + tag.key)
      }
    }
  }
}

///|
fn tagging_document(tags : Array[ObjectTag]) -> String {
  let mut out = "<Tagging><TagSet>"
  for tag in tags {
    out = out +
      "<Tag><Key>" +
      xml_escape(tag.key) +
      "</Key><Value>" +
      xml_escape(tag.value) +
      "</Value></Tag>"
  }
  out + "</TagSet></Tagging>"
}

///|
fn parse_object_tagging(body : String) -> ObjectTagging {
  let tags : Array[ObjectTag] = []
  for section in xml_sections(body, "Tag") {
    tags.push(ObjectTag::{
      key: or_empty(xml_first(section, "Key")),
      value: or_empty(xml_first(section, "Value")),
    })
  }
  ObjectTagging::{ tags, body, }
}
