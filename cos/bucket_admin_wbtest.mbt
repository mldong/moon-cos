///|
fn has_header(
  headers : Array[(String, String)],
  name : String,
  value : String,
) -> Bool {
  for pair in headers {
    if pair.0 == name && pair.1 == value {
      return true
    }
  }
  false
}

///|
test "bucket admin headers carry only non-empty options" {
  let headers = bucket_admin_headers(acl="private", storage_class="STANDARD")
  assert_true(has_header(headers, "x-cos-acl", "private"))
  assert_true(has_header(headers, "x-cos-storage-class", "STANDARD"))
  let empty = bucket_admin_headers(acl="", storage_class="")
  assert_eq(empty.length(), 0)
}
