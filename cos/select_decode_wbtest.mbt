///|
fn frame_bytes(event : String, payload : String) -> Bytes {
  let name = ":event-type"
  let headers : Array[Byte] = []
  headers.push(name.length().to_byte())
  headers.append(@utf8.encode(name.view()).to_array())
  headers.push(7)
  headers.push((event.length() >> 8).to_byte())
  headers.push((event.length() & 0xFF).to_byte())
  headers.append(@utf8.encode(event.view()).to_array())
  let payload_bytes = @utf8.encode(payload.view()).to_array()
  let total = 12 + headers.length() + payload_bytes.length() + 4
  let out : Array[Byte] = []
  out.push((total >> 24).to_byte())
  out.push(((total >> 16) & 0xFF).to_byte())
  out.push(((total >> 8) & 0xFF).to_byte())
  out.push((total & 0xFF).to_byte())
  out.push((headers.length() >> 24).to_byte())
  out.push(((headers.length() >> 16) & 0xFF).to_byte())
  out.push(((headers.length() >> 8) & 0xFF).to_byte())
  out.push((headers.length() & 0xFF).to_byte())
  out.push(0)
  out.push(0)
  out.push(0)
  out.push(0)
  out.append(headers)
  out.append(payload_bytes)
  out.append([0, 0, 0, 0])
  Bytes::from_array(out)
}

///|
test "event stream decoder keeps only Records payloads" {
  let stream = frame_bytes("Records", "a,b\n") + frame_bytes("Stats", "{}")
  assert_eq(@utf8.decode_lossy(select_records(stream)), "a,b\n")
}
