///|
/// 桶网站托管：`GET/PUT/DELETE /?website`。未配置时 404 读成 `None`。
pub(all) struct WebsiteConfig {
  index_suffix : String
  error_key : String?
}

///|
pub async fn Client::put_bucket_website(
  self : Client,
  bucket : String,
  index_suffix : String,
  error_key~ : String = "",
) -> Unit raise @error.CosError {
  if index_suffix.is_empty() {
    raise @error.BadParam("website index suffix is required")
  }
  let document = website_document(index_suffix, error_key)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("website", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_website(
  self : Client,
  bucket : String,
) -> WebsiteConfig? raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("website", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 {
            return None
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  parse_website(body)
}

///|
pub async fn Client::delete_bucket_website(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("website", "")])
  discard_body(response)
}

///|
fn website_document(index_suffix : String, error_key : String) -> String {
  let mut out = "<WebsiteConfiguration><IndexDocument><Suffix>" +
    xml_escape(index_suffix) +
    "</Suffix></IndexDocument>"
  if !error_key.is_empty() {
    out = out +
      "<ErrorDocument><Key>" +
      xml_escape(error_key) +
      "</Key></ErrorDocument>"
  }
  out + "</WebsiteConfiguration>"
}

///|
fn parse_website(body : String) -> WebsiteConfig? {
  let index = match xml_first(body, "Suffix") {
    Some(value) => value
    None => return None
  }
  Some(WebsiteConfig::{
    index_suffix: index,
    error_key: xml_first(body, "Key"),
  })
}
