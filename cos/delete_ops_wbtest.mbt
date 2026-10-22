///|
test "delete_objects document escapes keys and honors quiet" {
  let document = delete_objects_document(["a&b", "c<d"], true)
  assert_true(document.contains("<Quiet>true</Quiet>"))
  assert_true(document.contains("<Key>a&amp;b</Key>"))
  assert_true(document.contains("<Key>c&lt;d</Key>"))
  let plain = delete_objects_document(["a"], false)
  assert_true(!plain.contains("<Quiet>"))
}

///|
test "delete_objects content-md5 matches a fixed vector" {
  let body = @utf8.encode(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Delete><Object><Key>a</Key></Object></Delete>".view(),
  )
  assert_eq(delete_objects_content_md5(body), "GHTHOIjEhEx8oyGUt4LWEg==")
}

///|
test "delete_objects parses deleted and error sections" {
  let body = "<DeleteResult><Deleted><Key>a</Key></Deleted><Deleted><Key>b</Key></Deleted><Error><Key>c</Key><Code>AccessDenied</Code><Message>denied</Message></Error></DeleteResult>"
  let result = parse_delete_objects_result(body)
  assert_eq(result.deleted.length(), 2)
  assert_eq(result.deleted[0], "a")
  assert_eq(result.deleted[1], "b")
  assert_eq(result.errors.length(), 1)
  assert_eq(result.errors[0].key, "c")
  assert_eq(result.errors[0].code, "AccessDenied")
  assert_eq(result.errors[0].message, "denied")
  assert_eq(result.body, body)
}

///|
test "delete_objects parses an empty quiet response" {
  let result = parse_delete_objects_result("")
  assert_eq(result.deleted.length(), 0)
  assert_eq(result.errors.length(), 0)
}
