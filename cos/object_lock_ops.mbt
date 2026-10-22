///|
/// 桶对象锁：`GET/PUT /?object-lock`。腾讯 COS 的形状与 S3 同形
/// （官方 Python `put_bucket_object_lock` / `get_bucket_object_lock`，2026-10-22 现读）：
/// `ObjectLockEnabled` 加一条默认保留规则（模式 + Days/Years）。
/// 对象锁只能在建桶时开启；已有桶读口常见 404/409，写侧只落离线件。
pub(all) struct ObjectLockConfig {
  enabled : String
  mode : String
  days : Int32?
  years : Int32?
}

///|
pub fn ObjectLockConfig::new(
  enabled~ : String = "Enabled",
  mode~ : String = "COMPLIANCE",
) -> ObjectLockConfig {
  ObjectLockConfig::{ enabled, mode, days: None, years: None, }
}

///|
pub async fn Client::put_bucket_object_lock(
  self : Client,
  bucket : String,
  config : ObjectLockConfig,
) -> Unit raise @error.CosError {
  if config.enabled != "Enabled" && config.enabled != "Disabled" {
    raise @error.BadParam(
      "ObjectLockEnabled must be Enabled or Disabled, got " + config.enabled,
    )
  }
  if config.days is None && config.years is None {
    raise @error.BadParam("object lock needs Days or Years default retention")
  }
  let document = object_lock_document(config)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("object-lock", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_object_lock(
  self : Client,
  bucket : String,
) -> ObjectLockConfig? raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("object-lock", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 || details.status == 409 {
            return None
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  Some(parse_object_lock(body))
}

///|
fn object_lock_document(config : ObjectLockConfig) -> String {
  let mut out = "<ObjectLockConfiguration><ObjectLockEnabled>" +
    xml_escape(config.enabled) +
    "</ObjectLockEnabled><Rule><DefaultRetention><Mode>" +
    xml_escape(config.mode) +
    "</Mode>"
  match config.days {
    Some(days) => out = out + "<Days>" + days.to_string() + "</Days>"
    None => ()
  }
  match config.years {
    Some(years) => out = out + "<Years>" + years.to_string() + "</Years>"
    None => ()
  }
  out + "</DefaultRetention></Rule></ObjectLockConfiguration>"
}

///|
fn parse_object_lock(body : String) -> ObjectLockConfig {
  let rule = match xml_section_of(body, "DefaultRetention") {
    Some(text) => text
    None => ""
  }
  ObjectLockConfig::{
    enabled: xml_first(body, "ObjectLockEnabled").unwrap_or(""),
    mode: xml_first(rule, "Mode").unwrap_or(""),
    days: parse_optional_int32(xml_first(rule, "Days")),
    years: parse_optional_int32(xml_first(rule, "Years")),
  }
}
