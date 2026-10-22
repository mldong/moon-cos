///|
test "encryption document carries the algorithm" {
  assert_true(
    encryption_document("AES256").contains(
      "<SSEAlgorithm>AES256</SSEAlgorithm>",
    ),
  )
}
