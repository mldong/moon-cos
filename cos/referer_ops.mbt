///|
/// 桶防盗链：`GET/PUT/DELETE /?referer`。腾讯 COS 的 `RefererConfiguration`
/// 与 OSS 不同：状态（Enabled/Disabled）、名单类型（White-List/Black-List）、
/// 域名列表（`DomainList><Domain`）、空 Referer 策略（Allow/Deny）。
/// 字段名照官方 Python SDK `demo/bucket_referer.py`（2026-10-22 现读）。
pub(all) struct BucketReferer {
  status : String?
  referer_type : String?
  domains : Array[String]
  empty_refer_configuration : String?
}

///|
pub async fn Client::put_bucket_referer(
  self : Client,
  bucket : String,
  config : BucketReferer,
) -> Unit raise @error.CosError {
  check_referer(config)
  let document = referer_document(config)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("referer", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
/// 未配置时 COS 回 404 `NoSuchRefererConfiguration`；这一档落成空配置。
pub async fn Client::get_bucket_referer(
  self : Client,
  bucket : String,
) -> BucketReferer raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("referer", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 {
            return BucketReferer::{
              status: None,
              referer_type: None,
              domains: [],
              empty_refer_configuration: None,
            }
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  parse_referer(body)
}

///|
pub async fn Client::delete_bucket_referer(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("referer", "")])
  discard_body(response)
}

///|
fn check_referer(config : BucketReferer) -> Unit raise @error.CosError {
  match config.status {
    Some(status) =>
      if status != "Enabled" && status != "Disabled" {
        raise @error.BadParam(
          "referer status must be Enabled or Disabled, got " + status,
        )
      }
    None => ()
  }
  match config.referer_type {
    Some(kind) =>
      if kind != "White-List" && kind != "Black-List" {
        raise @error.BadParam(
          "referer type must be White-List or Black-List, got " + kind,
        )
      }
    None => ()
  }
}

///|
fn referer_document(config : BucketReferer) -> String {
  let mut out = "<RefererConfiguration>"
  match config.status {
    Some(status) => out = out + "<Status>" + xml_escape(status) + "</Status>"
    None => ()
  }
  match config.referer_type {
    Some(kind) =>
      out = out + "<RefererType>" + xml_escape(kind) + "</RefererType>"
    None => ()
  }
  out = out + "<DomainList>"
  for domain in config.domains {
    out = out + "<Domain>" + xml_escape(domain) + "</Domain>"
  }
  out = out + "</DomainList>"
  match config.empty_refer_configuration {
    Some(policy) =>
      out = out +
        "<EmptyReferConfiguration>" +
        xml_escape(policy) +
        "</EmptyReferConfiguration>"
    None => ()
  }
  out + "</RefererConfiguration>"
}

///|
fn parse_referer(body : String) -> BucketReferer {
  let domains = match xml_section_of(body, "DomainList") {
    None => []
    Some(section) => xml_all(section, "Domain")
  }
  BucketReferer::{
    status: xml_first(body, "Status"),
    referer_type: xml_first(body, "RefererType"),
    domains,
    empty_refer_configuration: xml_first(body, "EmptyReferConfiguration"),
  }
}
