///|
/// 桶复制：`GET/PUT/DELETE /?replication`。腾讯 COS 的 XML 是
/// `<ReplicationConfiguration><Role/><Rules><Rule>...`（官方 Python
/// `put_bucket_replication`，2026-10-22 现读）；规则里的目标桶与存储类在
/// `<Destination>` 下。未配置时读口回 404，落成 `None`。
pub(all) struct ReplicationRule {
  id : String
  prefix : String
  status : String
  destination_bucket : String
  storage_class : String
}

///|
pub(all) struct ReplicationConfig {
  role : String
  rules : Array[ReplicationRule]
}

///|
pub fn ReplicationRule::new(
  id : String,
  destination_bucket : String,
  status~ : String = "Enabled",
  prefix~ : String = "",
) -> ReplicationRule {
  ReplicationRule::{
    id,
    prefix,
    status,
    destination_bucket,
    storage_class: "",
  }
}

///|
pub async fn Client::put_bucket_replication(
  self : Client,
  bucket : String,
  config : ReplicationConfig,
) -> Unit raise @error.CosError {
  if config.rules.is_empty() {
    raise @error.BadParam("put_bucket_replication needs at least one rule")
  }
  for rule in config.rules {
    if rule.destination_bucket.is_empty() {
      raise @error.BadParam(
        "replication rule without a destination bucket: " + rule.id,
      )
    }
    if rule.status != "Enabled" && rule.status != "Disabled" {
      raise @error.BadParam(
        "replication rule status must be Enabled or Disabled, got " +
        rule.status,
      )
    }
  }
  let document = replication_document(config)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("replication", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_replication(
  self : Client,
  bucket : String,
) -> ReplicationConfig? raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("replication", "")]) catch {
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
  Some(parse_replication(body))
}

///|
pub async fn Client::delete_bucket_replication(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("replication", "")])
  discard_body(response)
}

///|
fn replication_document(config : ReplicationConfig) -> String {
  let mut out = "<ReplicationConfiguration>"
  if !config.role.is_empty() {
    out = out + "<Role>" + xml_escape(config.role) + "</Role>"
  }
  out = out + "<Rules>"
  for rule in config.rules {
    out = out + "<Rule><ID>" + xml_escape(rule.id) + "</ID>"
    out = out + "<Prefix>" + xml_escape(rule.prefix) + "</Prefix>"
    out = out + "<Status>" + xml_escape(rule.status) + "</Status>"
    out = out +
      "<Destination><Bucket>" +
      xml_escape(rule.destination_bucket) +
      "</Bucket>"
    if !rule.storage_class.is_empty() {
      out = out +
        "<StorageClass>" +
        xml_escape(rule.storage_class) +
        "</StorageClass>"
    }
    out = out + "</Destination></Rule>"
  }
  out + "</Rules></ReplicationConfiguration>"
}

///|
fn parse_replication(body : String) -> ReplicationConfig {
  let rules : Array[ReplicationRule] = []
  for section in xml_sections(body, "Rule") {
    let destination = match xml_section_of(section, "Destination") {
      Some(text) => text
      None => ""
    }
    rules.push(ReplicationRule::{
      id: xml_first(section, "ID").unwrap_or(""),
      prefix: xml_first(section, "Prefix").unwrap_or(""),
      status: xml_first(section, "Status").unwrap_or(""),
      destination_bucket: xml_first(destination, "Bucket").unwrap_or(""),
      storage_class: xml_first(destination, "StorageClass").unwrap_or(""),
    })
  }
  ReplicationConfig::{ role: xml_first(body, "Role").unwrap_or(""), rules, }
}
