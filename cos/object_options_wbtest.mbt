///|
fn header_value(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
test "object headers carry storage class and checksum" {
  let headers = object_headers(
    metadata=[],
    storage_class="IA",
    content_md5="md5-value",
  )
  assert_true(header_value(headers, "x-cos-storage-class") is Some("IA"))
  assert_true(header_value(headers, "content-md5") is Some("md5-value"))
}

///|
test "content md5 matches a fixed vector" {
  assert_eq(
    content_md5_of(@utf8.encode("abc".view())),
    "kAFQmDzST7DWlj99KOF/cg==",
  )
}

///|
test "conditional headers carry one condition" {
  let headers = conditional_headers(if_match="\"abc\"", if_none_match="")
  assert_true(header_value(headers, "if-match") is Some("\"abc\""))
  assert_true(header_value(headers, "if-none-match") is None)
}

///|
test "date conditions and copy source conditions are emitted" {
  let headers = conditional_headers(
    if_modified_since="Wed, 01 Jan 2020 00:00:00 GMT",
  )
  assert_true(header_value(headers, "if-modified-since") is Some(_))
  let copied = copy_source_conditional_headers(
    if_match="\"abc\"",
    if_none_match="",
    if_modified_since="",
    if_unmodified_since="Wed, 01 Jan 2020 00:00:00 GMT",
  )
  assert_true(header_value(copied, "x-cos-copy-source-if-match") is Some(_))
  assert_true(
    header_value(copied, "x-cos-copy-source-if-unmodified-since") is Some(_),
  )
}

///|
test "conditional headers reject both conditions" {
  let mut rejected = false
  try {
    let _ = conditional_headers(if_match="\"abc\"", if_none_match="\"def\"")
  } catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
