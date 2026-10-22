///|
/// 桶标签：`GET/PUT/DELETE /?tagging`。复用对象标签的 `Tagging/TagSet/Tag` XML；
/// 桶标签上限比对象标签宽，这里不套对象的 10 条上限，只拒空/重复键。
pub async fn Client::put_bucket_tagging(
  self : Client,
  bucket : String,
  tags : Array[ObjectTag],
) -> Unit raise @error.CosError {
  check_bucket_tags(tags)
  let document = tagging_document(tags)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("tagging", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_tagging(
  self : Client,
  bucket : String,
) -> ObjectTagging raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("tagging", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 {
            return ObjectTagging::{ tags: [], body: "", }
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  parse_object_tagging(body)
}

///|
pub async fn Client::delete_bucket_tagging(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("tagging", "")])
  discard_body(response)
}

///|
fn check_bucket_tags(tags : Array[ObjectTag]) -> Unit raise @error.CosError {
  if tags.is_empty() {
    raise @error.BadParam("put_bucket_tagging needs at least one tag")
  }
  for i in 0..<tags.length() {
    let tag = tags[i]
    if tag.key.is_empty() {
      raise @error.BadParam("bucket tag key must not be empty")
    }
    if tag.key.length() > 128 {
      raise @error.BadParam("bucket tag key exceeds 128 characters")
    }
    if tag.value.length() > 256 {
      raise @error.BadParam("bucket tag value exceeds 256 characters")
    }
    for j in (i + 1)..<tags.length() {
      if tag.key == tags[j].key {
        raise @error.BadParam("bucket tag keys must be unique: " + tag.key)
      }
    }
  }
}
