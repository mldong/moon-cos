///|
test "lifecycle document writes the COS filter and abort element" {
  let rules = [
    LifecycleRule::new("expire-logs", prefix="logs/")
    .with_expiration(days=Some(30))
    .with_transitions([
      LifecycleTransition::{
        days: Some(7),
        date: None,
        storage_class: "STANDARD_IA",
      },
    ])
    .with_abort_multipart(3),
  ]
  assert_eq(
    lifecycle_document(rules),
    "<LifecycleConfiguration><Rule><ID>expire-logs</ID><Filter><Prefix>logs/</Prefix></Filter>" +
    "<Status>Enabled</Status><Expiration><Days>30</Days></Expiration>" +
    "<Transition><Days>7</Days><StorageClass>STANDARD_IA</StorageClass></Transition>" +
    "<AbortIncompleteMultipartUpload><DaysAfterInitiation>3</DaysAfterInitiation>" +
    "</AbortIncompleteMultipartUpload></Rule></LifecycleConfiguration>",
  )
}

///|
test "lifecycle parse reads the COS filter prefix and days" {
  let sample = "<LifecycleConfiguration><Rule><ID>a</ID><Filter><Prefix>logs/</Prefix></Filter>" +
    "<Status>Enabled</Status><Expiration><Days>10</Days></Expiration>" +
    "<Transition><Days>5</Days><StorageClass>ARCHIVE</StorageClass></Transition>" +
    "<AbortIncompleteMultipartUpload><DaysAfterInitiation>2</DaysAfterInitiation>" +
    "</AbortIncompleteMultipartUpload></Rule>" +
    "<Rule><ID>b</ID><Filter><Prefix></Prefix></Filter><Status>Disabled</Status>" +
    "<Expiration><ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker></Expiration>" +
    "</Rule></LifecycleConfiguration>"
  let rules = parse_lifecycle_rules(sample)
  assert_eq(rules.length(), 2)
  assert_eq(rules[0].prefix, "logs/")
  assert_eq(rules[0].expiration_days, Some(10))
  assert_eq(rules[0].transitions[0].storage_class, "ARCHIVE")
  assert_eq(rules[0].abort_incomplete_multipart_days, Some(2))
  assert_eq(rules[1].expired_object_delete_marker, Some(true))
  assert_eq(rules[1].prefix, "")
}

///|
test "lifecycle parse accepts a prefix directly under Rule" {
  let sample = "<LifecycleConfiguration><Rule><ID>c</ID><Prefix>tmp/</Prefix>" +
    "<Status>Enabled</Status><Expiration><Days>1</Days></Expiration></Rule></LifecycleConfiguration>"
  let rules = parse_lifecycle_rules(sample)
  assert_eq(rules.length(), 1)
  assert_eq(rules[0].prefix, "tmp/")
}
