///|
/// 对象内查询：`POST /<key>?select&select-type=2`，body 是 `SelectRequest` XML，
/// 应答是 event-stream 帧。本版把原始字节交回调用方，帧解码留到下一层；
/// 只做 CSV 输入/输出，JSON 不在这一版。
pub async fn Client::select_object_csv(
  self : Client,
  bucket : String,
  key : String,
  expression : String,
  record_delimiter~ : String = "\n",
  field_delimiter~ : String = ",",
) -> Bytes raise @error.CosError {
  if expression.is_empty() {
    raise @error.BadParam("select_object_csv needs an expression")
  }
  let document = select_csv_document(
    expression,
    record_delimiter~,
    field_delimiter~,
  )
  let response = request(
    self,
    "POST",
    bucket~,
    key~,
    query=[("select", ""), ("select-type", "2")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  let raw = read_all(response.body)
  response.body.close()
  raw
}

///|
fn select_csv_document(
  expression : String,
  record_delimiter~ : String,
  field_delimiter~ : String,
) -> String {
  "<SelectRequest><Expression>" +
  xml_escape(expression) +
  "</Expression><ExpressionType>SQL</ExpressionType>" +
  "<InputSerialization><CSV><RecordDelimiter>" +
  xml_escape(record_delimiter) +
  "</RecordDelimiter><FieldDelimiter>" +
  xml_escape(field_delimiter) +
  "</FieldDelimiter></CSV></InputSerialization><OutputSerialization><CSV>" +
  "<RecordDelimiter>" +
  xml_escape(record_delimiter) +
  "</RecordDelimiter></CSV></OutputSerialization></SelectRequest>"
}
