///|
test "symlink headers carry the target and optional switches" {
  assert_eq(symlink_headers("target/key.txt"), [
    ("x-cos-symlink-target", "target/key.txt"),
  ])
  assert_eq(
    symlink_headers(
      "target/key.txt",
      forbid_overwrite=true,
      storage_class="STANDARD_IA",
      acl="private",
    ),
    [
      ("x-cos-symlink-target", "target/key.txt"),
      ("x-cos-forbid-overwrite", "true"),
      ("x-cos-storage-class", "STANDARD_IA"),
      ("x-cos-acl", "private"),
    ],
  )
}
