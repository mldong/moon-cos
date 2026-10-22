///|
/// 桶 CORS：`GET/PUT/DELETE /?cors`。规则按官方 XML 的 `CORSRule` 子元素读写。
pub(all) struct CorsRule {
  allowed_origins : Array[String]
  allowed_methods : Array[String]
  allowed_headers : Array[String]
  expose_headers : Array[String]
  max_age_seconds : Int32?
}

///|
pub async fn Client::put_bucket_cors(
  self : Client,
  bucket : String,
  rules : Array[CorsRule],
) -> Unit raise @error.CosError {
  check_cors_rules(rules)
  let document = cors_document(rules)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("cors", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_cors(
  self : Client,
  bucket : String,
) -> Array[CorsRule] raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("cors", "")]) catch {
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
  parse_cors_rules(body)
}

///|
pub async fn Client::delete_bucket_cors(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("cors", "")])
  discard_body(response)
}

///|
fn check_cors_rules(rules : Array[CorsRule]) -> Unit raise @error.CosError {
  if rules.is_empty() {
    raise @error.BadParam("put_bucket_cors needs at least one rule")
  }
  for rule in rules {
    if rule.allowed_origins.is_empty() || rule.allowed_methods.is_empty() {
      raise @error.BadParam("each CORS rule needs an origin and a method")
    }
    match rule.max_age_seconds {
      Some(age) =>
        if age < 0 {
          raise @error.BadParam("CORS max_age_seconds must be non-negative")
        }
      None => ()
    }
  }
}

///|
fn cors_document(rules : Array[CorsRule]) -> String {
  let mut out = "<CORSConfiguration>"
  for rule in rules {
    out = out + "<CORSRule>"
    for origin in rule.allowed_origins {
      out = out + "<AllowedOrigin>" + xml_escape(origin) + "</AllowedOrigin>"
    }
    for verb in rule.allowed_methods {
      out = out + "<AllowedMethod>" + xml_escape(verb) + "</AllowedMethod>"
    }
    for header in rule.allowed_headers {
      out = out + "<AllowedHeader>" + xml_escape(header) + "</AllowedHeader>"
    }
    for header in rule.expose_headers {
      out = out + "<ExposeHeader>" + xml_escape(header) + "</ExposeHeader>"
    }
    match rule.max_age_seconds {
      Some(age) =>
        out = out + "<MaxAgeSeconds>" + age.to_string() + "</MaxAgeSeconds>"
      None => ()
    }
    out = out + "</CORSRule>"
  }
  out + "</CORSConfiguration>"
}

///|
fn parse_cors_rules(body : String) -> Array[CorsRule] {
  let rules : Array[CorsRule] = []
  for section in xml_sections(body, "CORSRule") {
    rules.push(CorsRule::{
      allowed_origins: xml_all(section, "AllowedOrigin"),
      allowed_methods: xml_all(section, "AllowedMethod"),
      allowed_headers: xml_all(section, "AllowedHeader"),
      expose_headers: xml_all(section, "ExposeHeader"),
      max_age_seconds: parse_optional_int32(xml_first(section, "MaxAgeSeconds")),
    })
  }
  rules
}

///|
fn parse_optional_int32(text : String?) -> Int32? {
  match text {
    None => None
    Some(value) =>
      if value.is_empty() {
        None
      } else {
        Some(@string.parse_int(value.view(), base=10) catch { _ => 0 })
      }
  }
}
