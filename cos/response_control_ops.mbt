///|
/// 响应内容控制：`GET/PUT/DELETE /?response-control`。腾讯 COS 的 XML 根是
/// `ResponseControlConfiguration`，参数白名单放在
/// `ControlParamList><Param` 里（官方 Python `put_bucket_response_control` 与 `ut/test.py`，
/// 2026-10-22 现读）。未配置时读口回 404，落成空数组。
pub async fn Client::put_bucket_response_control(
  self : Client,
  bucket : String,
  params : Array[String],
) -> Unit raise @error.CosError {
  if params.is_empty() {
    raise @error.BadParam(
      "put_bucket_response_control needs at least one param",
    )
  }
  let document = response_control_document(params)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("response-control", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_response_control(
  self : Client,
  bucket : String,
) -> Array[String] raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("response-control", "")]) catch {
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
  parse_response_control(body)
}

///|
pub async fn Client::delete_bucket_response_control(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[
    ("response-control", ""),
  ])
  discard_body(response)
}

///|
fn response_control_document(params : Array[String]) -> String {
  let mut out = "<ResponseControlConfiguration><ControlParamList>"
  for param in params {
    out = out + "<Param>" + xml_escape(param) + "</Param>"
  }
  out + "</ControlParamList></ResponseControlConfiguration>"
}

///|
fn parse_response_control(body : String) -> Array[String] {
  match xml_section_of(body, "ControlParamList") {
    None => []
    Some(section) => xml_all(section, "Param")
  }
}
