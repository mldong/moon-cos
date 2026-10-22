///|
test "object lock document writes enabled and retention days" {
  let config = ObjectLockConfig::{
    enabled: "Enabled",
    mode: "COMPLIANCE",
    days: Some(30),
    years: None,
  }
  assert_eq(
    object_lock_document(config),
    "<ObjectLockConfiguration><ObjectLockEnabled>Enabled</ObjectLockEnabled>" +
    "<Rule><DefaultRetention><Mode>COMPLIANCE</Mode><Days>30</Days>" +
    "</DefaultRetention></Rule></ObjectLockConfiguration>",
  )
}

///|
test "object lock parse reads rule and years" {
  let body = "<ObjectLockConfiguration><ObjectLockEnabled>Enabled</ObjectLockEnabled>" +
    "<Rule><DefaultRetention><Mode>GOVERNANCE</Mode><Years>2</Years>" +
    "</DefaultRetention></Rule></ObjectLockConfiguration>"
  let config = parse_object_lock(body)
  assert_eq(config.enabled, "Enabled")
  assert_eq(config.mode, "GOVERNANCE")
  assert_eq(config.days, None)
  assert_eq(config.years, Some(2))
}
