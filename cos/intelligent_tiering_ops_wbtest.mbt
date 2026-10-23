///|
test "intelligent tiering document writes Enable and days" {
  assert_eq(
    intelligent_tiering_document(IntelligentTieringConfig::new(days=30)),
    "<IntelligentTieringConfiguration><Status>Enable</Status>" +
    "<Transition><Days>30</Days></Transition></IntelligentTieringConfiguration>",
  )
}

///|
test "intelligent tiering parse reads status and days" {
  let config = parse_intelligent_tiering(
    "<IntelligentTieringConfiguration><Status>Disable</Status>" +
    "<Transition><Days>60</Days></Transition></IntelligentTieringConfiguration>",
  )
  assert_eq(config.status, "Disable")
  assert_eq(config.days, Some(60))
}
