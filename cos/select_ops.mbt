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

///|
/// 把 event-stream 解成 Records 载荷的拼接。帧格式照 AWS/OSS 的二进制协议：
/// `[总长 u32][头长 u32][前导 CRC u32][头块][载荷][消息 CRC u32]`，头块里是
/// `[名长 u8][名][类型 u8][值长 u16][值]`。本函数**不校验两段 CRC**（只跳过），
/// 只按 `:event-type == "Records"` 取载荷；Stats/End/Progress 帧忽略。
pub fn select_records(event_stream : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut cursor = 0
  let total = event_stream.length()
  while cursor + 12 <= total {
    let frame_len = read_u32_be(event_stream, cursor)
    let headers_len = read_u32_be(event_stream, cursor + 4)
    if frame_len < 16 || cursor + frame_len > total {
      break
    }
    let headers_start = cursor + 12
    let payload_start = headers_start + headers_len
    let payload_end = cursor + frame_len - 4
    if payload_start > payload_end {
      break
    }
    let event_type = frame_event_type(
      event_stream, headers_start, payload_start,
    )
    if event_type == "Records" {
      out.append(event_stream[payload_start:payload_end].to_owned().to_array())
    }
    cursor = cursor + frame_len
  }
  Bytes::from_array(out)
}

///|
fn frame_event_type(data : Bytes, start : Int32, limit : Int32) -> String {
  let mut i = start
  let mut event = ""
  while i < limit {
    let name_len = data[i].to_int()
    i = i + 1
    if i + name_len > limit {
      break
    }
    let name = @utf8.decode_lossy(data[i:i + name_len])
    i = i + name_len
    if i + 3 > limit {
      break
    }
    let kind = data[i].to_int()
    i = i + 1
    let value_len = (data[i].to_int() << 8) + data[i + 1].to_int()
    i = i + 2
    if i + value_len > limit {
      break
    }
    if kind == 7 && name == ":event-type" {
      event = @utf8.decode_lossy(data[i:i + value_len])
    }
    i = i + value_len
  }
  event
}

///|
fn read_u32_be(data : Bytes, at : Int32) -> Int32 {
  (data[at].to_int() << 24) +
  (data[at + 1].to_int() << 16) +
  (data[at + 2].to_int() << 8) +
  data[at + 3].to_int()
}

///|
/// 选择并解码：`select_object_csv` + [select_records]，直接给 Records 载荷。
pub async fn Client::select_object_csv_records(
  self : Client,
  bucket : String,
  key : String,
  expression : String,
  record_delimiter~ : String = "\n",
  field_delimiter~ : String = ",",
) -> Bytes raise @error.CosError {
  let stream = self.select_object_csv(
    bucket,
    key,
    expression,
    record_delimiter~,
    field_delimiter~,
  )
  select_records(stream)
}
