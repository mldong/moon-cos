///|
/// 桶日志：`GET/PUT /?logging`。官方 COS Python SDK 只暴露 Put/Get，未暴露 Delete。
pub(all) struct BucketLogging {
  target_bucket : String
  target_prefix : String
}

///|
pub(all) struct BucketLoggingStatus {
  enabled : BucketLogging?
  body : String
}

///|
pub async fn Client::put_bucket_logging(
  self : Client,
  bucket : String,
  target_bucket : String,
  target_prefix~ : String = "",
) -> Unit raise @error.CosError {
  if target_bucket.is_empty() {
    raise @error.BadParam("logging target bucket is required")
  }
  let document = logging_document(target_bucket, target_prefix)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("logging", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_logging(
  self : Client,
  bucket : String,
) -> BucketLoggingStatus raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("logging", "")])
  let body = response_body_text(response.body, response.status)
  parse_logging(body)
}

///|
fn logging_document(target_bucket : String, target_prefix : String) -> String {
  "<BucketLoggingStatus><LoggingEnabled><TargetBucket>" +
  xml_escape(target_bucket) +
  "</TargetBucket><TargetPrefix>" +
  xml_escape(target_prefix) +
  "</TargetPrefix></LoggingEnabled></BucketLoggingStatus>"
}

///|
fn parse_logging(body : String) -> BucketLoggingStatus {
  let enabled = match xml_sections(body, "LoggingEnabled") {
    [] => None
    sections =>
      Some(BucketLogging::{
        target_bucket: or_empty(xml_first(sections[0], "TargetBucket")),
        target_prefix: or_empty(xml_first(sections[0], "TargetPrefix")),
      })
  }
  BucketLoggingStatus::{ enabled, body, }
}
