///|
/// 桶生命周期：`GET/PUT/DELETE /?lifecycle`。规则按腾讯 COS 的 XML 读写：
/// 前缀在 `<Filter><Prefix>` 里（OSS/OBS 是 Rule 直下），未完成分片清理叫
/// `<AbortIncompleteMultipartUpload><DaysAfterInitiation>`。字段覆盖官方 Python SDK
/// 的 Rule 子集：ID／前缀／状态／过期／沉降／未完成分片／非当前版本过期。
pub(all) struct LifecycleTransition {
  days : Int32?
  date : String?
  storage_class : String
}

///|
pub(all) struct LifecycleRule {
  id : String
  prefix : String
  status : String
  expiration_days : Int32?
  expiration_date : String?
  expired_object_delete_marker : Bool?
  transitions : Array[LifecycleTransition]
  abort_incomplete_multipart_days : Int32?
  noncurrent_version_expiration_days : Int32?
}

///|
pub fn LifecycleRule::new(
  id : String,
  prefix~ : String = "",
  status~ : String = "Enabled",
) -> LifecycleRule {
  LifecycleRule::{
    id,
    prefix,
    status,
    expiration_days: None,
    expiration_date: None,
    expired_object_delete_marker: None,
    transitions: [],
    abort_incomplete_multipart_days: None,
    noncurrent_version_expiration_days: None,
  }
}

///|
pub fn LifecycleRule::with_expiration(
  self : LifecycleRule,
  days~ : Int32? = None,
  date~ : String? = None,
  expired_object_delete_marker~ : Bool? = None,
) -> LifecycleRule {
  LifecycleRule::{
    id: self.id,
    prefix: self.prefix,
    status: self.status,
    expiration_days: days,
    expiration_date: date,
    expired_object_delete_marker,
    transitions: self.transitions,
    abort_incomplete_multipart_days: self.abort_incomplete_multipart_days,
    noncurrent_version_expiration_days: self.noncurrent_version_expiration_days,
  }
}

///|
pub fn LifecycleRule::with_transitions(
  self : LifecycleRule,
  transitions : Array[LifecycleTransition],
) -> LifecycleRule {
  LifecycleRule::{
    id: self.id,
    prefix: self.prefix,
    status: self.status,
    expiration_days: self.expiration_days,
    expiration_date: self.expiration_date,
    expired_object_delete_marker: self.expired_object_delete_marker,
    transitions,
    abort_incomplete_multipart_days: self.abort_incomplete_multipart_days,
    noncurrent_version_expiration_days: self.noncurrent_version_expiration_days,
  }
}

///|
pub fn LifecycleRule::with_abort_multipart(
  self : LifecycleRule,
  days : Int32,
) -> LifecycleRule {
  LifecycleRule::{
    id: self.id,
    prefix: self.prefix,
    status: self.status,
    expiration_days: self.expiration_days,
    expiration_date: self.expiration_date,
    expired_object_delete_marker: self.expired_object_delete_marker,
    transitions: self.transitions,
    abort_incomplete_multipart_days: Some(days),
    noncurrent_version_expiration_days: self.noncurrent_version_expiration_days,
  }
}

///|
pub fn LifecycleRule::with_noncurrent_expiration(
  self : LifecycleRule,
  days : Int32,
) -> LifecycleRule {
  LifecycleRule::{
    id: self.id,
    prefix: self.prefix,
    status: self.status,
    expiration_days: self.expiration_days,
    expiration_date: self.expiration_date,
    expired_object_delete_marker: self.expired_object_delete_marker,
    transitions: self.transitions,
    abort_incomplete_multipart_days: self.abort_incomplete_multipart_days,
    noncurrent_version_expiration_days: Some(days),
  }
}

///|
pub async fn Client::put_bucket_lifecycle(
  self : Client,
  bucket : String,
  rules : Array[LifecycleRule],
) -> Unit raise @error.CosError {
  check_lifecycle_rules(rules)
  let document = lifecycle_document(rules)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("lifecycle", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
/// 未配置时 COS 回 404 `NoSuchLifecycleConfiguration`；这一档落成空数组。
pub async fn Client::get_bucket_lifecycle(
  self : Client,
  bucket : String,
) -> Array[LifecycleRule] raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("lifecycle", "")]) catch {
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
  parse_lifecycle_rules(body)
}

///|
pub async fn Client::delete_bucket_lifecycle(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("lifecycle", "")])
  discard_body(response)
}

///|
fn check_lifecycle_rules(
  rules : Array[LifecycleRule],
) -> Unit raise @error.CosError {
  if rules.is_empty() {
    raise @error.BadParam("put_bucket_lifecycle needs at least one rule")
  }
  for rule in rules {
    if rule.status != "Enabled" && rule.status != "Disabled" {
      raise @error.BadParam(
        "lifecycle rule status must be Enabled or Disabled, got " + rule.status,
      )
    }
    let mut has_action = !rule.transitions.is_empty()
    if rule.expiration_days is Some(_) {
      has_action = true
    }
    if rule.expiration_date is Some(_) {
      has_action = true
    }
    if rule.expired_object_delete_marker is Some(_) {
      has_action = true
    }
    if rule.abort_incomplete_multipart_days is Some(_) {
      has_action = true
    }
    if rule.noncurrent_version_expiration_days is Some(_) {
      has_action = true
    }
    if !has_action {
      raise @error.BadParam("lifecycle rule without any action: " + rule.id)
    }
  }
}

///|
fn lifecycle_document(rules : Array[LifecycleRule]) -> String {
  let mut out = "<LifecycleConfiguration>"
  for rule in rules {
    out = out + "<Rule><ID>" + xml_escape(rule.id) + "</ID>"
    out = out +
      "<Filter><Prefix>" +
      xml_escape(rule.prefix) +
      "</Prefix></Filter>"
    out = out + "<Status>" + xml_escape(rule.status) + "</Status>"
    out = out + expiration_element(rule)
    for transition in rule.transitions {
      out = out + "<Transition>"
      match transition.days {
        Some(days) => out = out + "<Days>" + days.to_string() + "</Days>"
        None => ()
      }
      match transition.date {
        Some(date) => out = out + "<Date>" + xml_escape(date) + "</Date>"
        None => ()
      }
      out = out +
        "<StorageClass>" +
        xml_escape(transition.storage_class) +
        "</StorageClass></Transition>"
    }
    match rule.abort_incomplete_multipart_days {
      Some(days) =>
        out = out +
          "<AbortIncompleteMultipartUpload><DaysAfterInitiation>" +
          days.to_string() +
          "</DaysAfterInitiation></AbortIncompleteMultipartUpload>"
      None => ()
    }
    match rule.noncurrent_version_expiration_days {
      Some(days) =>
        out = out +
          "<NoncurrentVersionExpiration><NoncurrentDays>" +
          days.to_string() +
          "</NoncurrentDays></NoncurrentVersionExpiration>"
      None => ()
    }
    out = out + "</Rule>"
  }
  out + "</LifecycleConfiguration>"
}

///|
fn expiration_element(rule : LifecycleRule) -> String {
  let has_any = rule.expiration_days is Some(_) ||
    rule.expiration_date is Some(_) ||
    rule.expired_object_delete_marker is Some(_)
  if !has_any {
    return ""
  }
  let mut out = "<Expiration>"
  match rule.expiration_days {
    Some(days) => out = out + "<Days>" + days.to_string() + "</Days>"
    None => ()
  }
  match rule.expiration_date {
    Some(date) => out = out + "<Date>" + xml_escape(date) + "</Date>"
    None => ()
  }
  match rule.expired_object_delete_marker {
    Some(flag) =>
      out = out +
        "<ExpiredObjectDeleteMarker>" +
        flag.to_string() +
        "</ExpiredObjectDeleteMarker>"
    None => ()
  }
  out + "</Expiration>"
}

///|
fn parse_lifecycle_rules(body : String) -> Array[LifecycleRule] {
  let rules : Array[LifecycleRule] = []
  for section in xml_sections(body, "Rule") {
    let expiration = xml_section_of(section, "Expiration")
    let abort = xml_section_of(section, "AbortIncompleteMultipartUpload")
    let abort_days = match abort {
      None => None
      Some(text) => parse_optional_int32(xml_first(text, "DaysAfterInitiation"))
    }
    let noncurrent = xml_section_of(section, "NoncurrentVersionExpiration")
    let noncurrent_days = match noncurrent {
      None => None
      Some(text) => parse_optional_int32(xml_first(text, "NoncurrentDays"))
    }
    rules.push(LifecycleRule::{
      id: xml_first(section, "ID").unwrap_or(""),
      prefix: rule_prefix(section),
      status: xml_first(section, "Status").unwrap_or(""),
      expiration_days: match expiration {
        None => None
        Some(text) => parse_optional_int32(xml_first(text, "Days"))
      },
      expiration_date: match expiration {
        None => None
        Some(text) => xml_first(text, "Date")
      },
      expired_object_delete_marker: match expiration {
        None => None
        Some(text) =>
          parse_optional_bool(xml_first(text, "ExpiredObjectDeleteMarker"))
      },
      transitions: parse_transitions(section),
      abort_incomplete_multipart_days: abort_days,
      noncurrent_version_expiration_days: noncurrent_days,
    })
  }
  rules
}

///|
/// COS 的前缀在 `<Filter><Prefix>` 里；兼容直挂 `<Prefix>` 的回包形状。
fn rule_prefix(section : String) -> String {
  match xml_section_of(section, "Filter") {
    Some(filter) =>
      match xml_first(filter, "Prefix") {
        Some(prefix) => prefix
        None => ""
      }
    None => xml_first(section, "Prefix").unwrap_or("")
  }
}

///|
fn parse_transitions(section : String) -> Array[LifecycleTransition] {
  let out : Array[LifecycleTransition] = []
  for part in xml_sections(section, "Transition") {
    out.push(LifecycleTransition::{
      days: parse_optional_int32(xml_first(part, "Days")),
      date: xml_first(part, "Date"),
      storage_class: xml_first(part, "StorageClass").unwrap_or(""),
    })
  }
  out
}

///|
fn xml_section_of(text : String, tag : String) -> String? {
  let sections = xml_sections(text, tag)
  if sections.is_empty() {
    None
  } else {
    Some(sections[0])
  }
}

///|
fn parse_optional_bool(text : String?) -> Bool? {
  match text {
    None => None
    Some(value) =>
      if value == "true" {
        Some(true)
      } else if value == "false" {
        Some(false)
      } else {
        None
      }
  }
}
