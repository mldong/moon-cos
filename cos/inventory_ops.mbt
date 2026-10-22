///|
/// 桶清单：`PUT/GET/DELETE /?inventory&id=<id>` 与列表 `GET /?inventory`
/// （官方 Python `put_bucket_inventory` / `list_bucket_inventory_configurations`，
/// 2026-10-22 现读）。COS 的目标节点叫 `COSBucketDestination`，字段与 OSS 同形；
/// 本版覆盖格式／账号／桶／前缀、调度频率、版本口径、过滤前缀与可选字段。
pub(all) struct InventoryConfig {
  id : String
  is_enabled : Bool
  format : String
  destination_bucket : String
  destination_prefix : String
  account_id : String
  frequency : String
  included_versions : String
  filter_prefix : String
  optional_fields : Array[String]
}

///|
pub fn InventoryConfig::new(
  id : String,
  destination_bucket : String,
  format~ : String = "CSV",
  frequency~ : String = "Weekly",
) -> InventoryConfig {
  InventoryConfig::{
    id,
    is_enabled: true,
    format,
    destination_bucket,
    destination_prefix: "",
    account_id: "",
    frequency,
    included_versions: "All",
    filter_prefix: "",
    optional_fields: [],
  }
}

///|
pub async fn Client::put_bucket_inventory(
  self : Client,
  bucket : String,
  config : InventoryConfig,
) -> Unit raise @error.CosError {
  if config.id.is_empty() {
    raise @error.BadParam("put_bucket_inventory needs an inventory id")
  }
  if config.destination_bucket.is_empty() {
    raise @error.BadParam("put_bucket_inventory needs a destination bucket")
  }
  let document = inventory_document(config)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("inventory", ""), ("id", config.id)],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_inventory(
  self : Client,
  bucket : String,
  id : String,
) -> InventoryConfig? raise @error.CosError {
  if id.is_empty() {
    raise @error.BadParam("get_bucket_inventory needs an inventory id")
  }
  let response = request(self, "GET", bucket~, query=[
    ("inventory", ""),
    ("id", id),
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
  Some(parse_inventory(body))
}

///|
pub async fn Client::delete_bucket_inventory(
  self : Client,
  bucket : String,
  id : String,
) -> Unit raise @error.CosError {
  if id.is_empty() {
    raise @error.BadParam("delete_bucket_inventory needs an inventory id")
  }
  let response = request(self, "DELETE", bucket~, query=[
    ("inventory", ""),
    ("id", id),
  ])
  discard_body(response)
}

///|
pub async fn Client::list_bucket_inventories(
  self : Client,
  bucket : String,
) -> Array[InventoryConfig] raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("inventory", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 {
            return []
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  parse_inventories(body)
}

///|
fn inventory_document(config : InventoryConfig) -> String {
  let mut out = "<InventoryConfiguration><Id>" + xml_escape(config.id) + "</Id>"
  out = out + "<IsEnabled>" + config.is_enabled.to_string() + "</IsEnabled>"
  out = out + "<Destination><COSBucketDestination>"
  out = out + "<Format>" + xml_escape(config.format) + "</Format>"
  if !config.account_id.is_empty() {
    out = out + "<AccountId>" + xml_escape(config.account_id) + "</AccountId>"
  }
  out = out + "<Bucket>" + xml_escape(config.destination_bucket) + "</Bucket>"
  if !config.destination_prefix.is_empty() {
    out = out + "<Prefix>" + xml_escape(config.destination_prefix) + "</Prefix>"
  }
  out = out + "</COSBucketDestination></Destination>"
  out = out +
    "<Schedule><Frequency>" +
    xml_escape(config.frequency) +
    "</Frequency></Schedule>"
  if !config.filter_prefix.is_empty() {
    out = out +
      "<Filter><Prefix>" +
      xml_escape(config.filter_prefix) +
      "</Prefix></Filter>"
  }
  out = out +
    "<IncludedObjectVersions>" +
    xml_escape(config.included_versions) +
    "</IncludedObjectVersions>"
  if !config.optional_fields.is_empty() {
    out = out + "<OptionalFields>"
    for field in config.optional_fields {
      out = out + "<Field>" + xml_escape(field) + "</Field>"
    }
    out = out + "</OptionalFields>"
  }
  out + "</InventoryConfiguration>"
}

///|
fn parse_inventories(body : String) -> Array[InventoryConfig] {
  let out : Array[InventoryConfig] = []
  for section in xml_sections(body, "InventoryConfiguration") {
    out.push(parse_inventory(section))
  }
  out
}

///|
fn parse_inventory(section : String) -> InventoryConfig {
  let destination = match xml_section_of(section, "COSBucketDestination") {
    Some(text) => text
    None => ""
  }
  let filter = match xml_section_of(section, "Filter") {
    Some(text) => text
    None => ""
  }
  let schedule = match xml_section_of(section, "Schedule") {
    Some(text) => text
    None => ""
  }
  let fields = match xml_section_of(section, "OptionalFields") {
    Some(text) => xml_all(text, "Field")
    None => []
  }
  InventoryConfig::{
    id: xml_first(section, "Id").unwrap_or(""),
    is_enabled: xml_first(section, "IsEnabled") == Some("true"),
    format: xml_first(destination, "Format").unwrap_or(""),
    destination_bucket: xml_first(destination, "Bucket").unwrap_or(""),
    destination_prefix: xml_first(destination, "Prefix").unwrap_or(""),
    account_id: xml_first(destination, "AccountId").unwrap_or(""),
    frequency: xml_first(schedule, "Frequency").unwrap_or(""),
    included_versions: xml_first(section, "IncludedObjectVersions").unwrap_or(
      "",
    ),
    filter_prefix: xml_first(filter, "Prefix").unwrap_or(""),
    optional_fields: fields,
  }
}
