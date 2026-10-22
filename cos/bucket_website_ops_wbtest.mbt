///|
test "website document and parser round-trip" {
  match parse_website(website_document("index.html", "error.html")) {
    Some(config) => {
      assert_eq(config.index_suffix, "index.html")
      assert_eq(config.error_key, Some("error.html"))
    }
    None => assert_true(false)
  }
}

///|
test "website parser returns none without index document" {
  match parse_website("<WebsiteConfiguration/>") {
    None => ()
    Some(_) => assert_true(false)
  }
}
