///|
test "resume state text keeps upload id, offset and etags" {
  assert_eq(
    resume_state_text("upload-1", 102400, [(1, "etag-a"), (2, "etag-b")]),
    "upload-1|102400|1:etag-a,2:etag-b",
  )
  assert_eq(resume_state_text("upload-1", 0, []), "upload-1|0|")
}
