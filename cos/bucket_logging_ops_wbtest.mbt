///|
test "logging document and parser round-trip" {
  match parse_logging(logging_document("log-bucket", "logs/")).enabled {
    Some(value) => {
      assert_eq(value.target_bucket, "log-bucket")
      assert_eq(value.target_prefix, "logs/")
    }
    None => assert_true(false)
  }
}

///|
test "logging parser returns none when disabled" {
  match parse_logging("<BucketLoggingStatus/>").enabled {
    None => ()
    Some(_) => assert_true(false)
  }
}
