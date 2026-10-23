///|
/// 自定义域：`GET/PUT/DELETE /?domain`。腾讯 COS 的 XML 根是
/// `DomainConfiguration`，每条规则含 Name／Type／Status／ForcedReplacement
/// （官方 Python `put_bucket_domain` 与 `demo/bucket_domain.py`，2026-10-22 现读）。
pub(all) struct DomainRule {
  name : String
  kind : String
  status : String
  forced_replacement : String
}

///|
pub fn DomainRule::new(
  name : String,
  kind~ : String = "REST",
  status~ : String = "ENABLED",
) -> DomainRule {
  DomainRule::{ name, kind, status, forced_replacement: "CNAME", }
}

///|
pub async fn Client::put_bucket_domain(
  self : Client,
  bucket : String,
  rules : Array[DomainRule],
) -> Unit raise @error.CosError {
  if rules.is_empty() {
    raise @error.BadParam("put_bucket_domain needs at least one rule")
  }
  for rule in rules {
    if rule.name.is_empty() {
      raise @error.BadParam("domain rule without a name")
    }
  }
  let document = domain_document(rules)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("domain", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_domain(
  self : Client,
  bucket : String,
) -> Array[DomainRule] raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("domain", "")])
  let body = response_body_text(response.body, response.status)
  parse_domains(body)
}

///|
pub async fn Client::delete_bucket_domain(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("domain", "")])
  discard_body(response)
}

///|
fn domain_document(rules : Array[DomainRule]) -> String {
  let mut out = "<DomainConfiguration>"
  for rule in rules {
    out = out + "<DomainRule><Name>" + xml_escape(rule.name) + "</Name>"
    out = out + "<Type>" + xml_escape(rule.kind) + "</Type>"
    out = out + "<Status>" + xml_escape(rule.status) + "</Status>"
    out = out +
      "<ForcedReplacement>" +
      xml_escape(rule.forced_replacement) +
      "</ForcedReplacement></DomainRule>"
  }
  out + "</DomainConfiguration>"
}

///|
fn parse_domains(body : String) -> Array[DomainRule] {
  let out : Array[DomainRule] = []
  for section in xml_sections(body, "DomainRule") {
    out.push(DomainRule::{
      name: xml_first(section, "Name").unwrap_or(""),
      kind: xml_first(section, "Type").unwrap_or(""),
      status: xml_first(section, "Status").unwrap_or(""),
      forced_replacement: xml_first(section, "ForcedReplacement").unwrap_or(""),
    })
  }
  out
}
