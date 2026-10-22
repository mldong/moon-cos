///|
/// 追加写：`POST /<key>?append&position=N`。
pub async fn Client::append_object(
  self : Client,
  bucket : String,
  key : String,
  data : Bytes,
  position~ : Int64 = 0L,
  content_type~ : String = "",
) -> AppendResult raise @error.CosError {
  if position < 0L {
    raise @error.BadParam("append position must be non-negative")
  }
  let headers : Array[(String, String)] = []
  if !content_type.is_empty() {
    headers.push(("content-type", content_type))
  }
  let response = request(
    self,
    "POST",
    bucket~,
    key~,
    query=append_query(position),
    headers~,
    body=@transport.RequestBody::Bytes(data),
  )
  discard_body(response)
  AppendResult::{
    next_position: header_int64(response.headers, "x-cos-next-append-position"),
    etag: header_of(response.headers, "etag"),
    body: "",
  }
}

///|
fn append_query(position : Int64) -> Array[(String, String)] {
  [("append", ""), ("position", position.to_string())]
}

///|
fn header_int64(headers : Array[@transport.Header], name : String) -> Int64? {
  match header_of(headers, name) {
    None => None
    Some(value) =>
      if value.is_empty() {
        None
      } else {
        Some(@string.parse_int64(value.view(), base=10) catch { _ => 0L })
      }
  }
}
