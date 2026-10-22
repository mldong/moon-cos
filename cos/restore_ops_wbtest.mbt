///|
test "restore document carries days and optional tier" {
  assert_eq(
    restore_document(3, "Standard"),
    "<RestoreRequest><Days>3</Days><Tier>Standard</Tier></RestoreRequest>",
  )
  assert_eq(
    restore_document(1, ""),
    "<RestoreRequest><Days>1</Days></RestoreRequest>",
  )
}
