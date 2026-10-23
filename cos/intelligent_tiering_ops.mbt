///|
/// 智能分层：`GET/PUT /?intelligenttiering`。腾讯 COS 的 XML 根是
/// `IntelligentTieringConfiguration`，`Status` 用 `Enable` 而不是 `Enabled`，
/// 另带一条 `Transition><Days>`（官方 Python `put_bucket_intelligenttiering`，2026-10-22 现读）。
pub(all) struct IntelligentTieringConfig {
  status : String
  days : Int32?
}

///|
pub fn IntelligentTieringConfig::new(
  days~ : Int32 = 30,
) -> IntelligentTieringConfig {
  IntelligentTieringConfig::{ status: "Enable", days: Some(days), }
}

///|
pub async fn Client::put_bucket_intelligent_tiering(
  self : Client,
  bucket : String,
  config : IntelligentTieringConfig,
) -> Unit raise @error.CosError {
  if config.status != "Enable" && config.status != "Disable" {
    raise @error.BadParam(
      "intelligent tiering status must be Enable or Disable, got " +
      config.status,
    )
  }
  let document = intelligent_tiering_document(config)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("intelligenttiering", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_intelligent_tiering(
  self : Client,
  bucket : String,
) -> IntelligentTieringConfig? raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[
    ("intelligenttiering", ""),
  ]) catch {
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
  Some(parse_intelligent_tiering(body))
}

///|
fn intelligent_tiering_document(config : IntelligentTieringConfig) -> String {
  let mut out = "<IntelligentTieringConfiguration><Status>" +
    xml_escape(config.status) +
    "</Status>"
  match config.days {
    Some(days) =>
      out = out +
        "<Transition><Days>" +
        days.to_string() +
        "</Days></Transition>"
    None => ()
  }
  out + "</IntelligentTieringConfiguration>"
}

///|
fn parse_intelligent_tiering(body : String) -> IntelligentTieringConfig {
  let transition = match xml_section_of(body, "Transition") {
    Some(text) => text
    None => ""
  }
  IntelligentTieringConfig::{
    status: xml_first(body, "Status").unwrap_or(""),
    days: parse_optional_int32(xml_first(transition, "Days")),
  }
}
