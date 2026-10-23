///|
test "domain document writes rule fields" {
  assert_eq(
    domain_document([DomainRule::new("www.example.com")]),
    "<DomainConfiguration><DomainRule><Name>www.example.com</Name><Type>REST</Type>" +
    "<Status>ENABLED</Status><ForcedReplacement>CNAME</ForcedReplacement>" +
    "</DomainRule></DomainConfiguration>",
  )
}

///|
test "domain parse reads rules" {
  let body = "<DomainConfiguration><DomainRule><Name>a.example.com</Name>" +
    "<Type>WEBSITE</Type><Status>DISABLED</Status><ForcedReplacement>TXT</ForcedReplacement>" +
    "</DomainRule></DomainConfiguration>"
  let rules = parse_domains(body)
  assert_eq(rules.length(), 1)
  assert_eq(rules[0].kind, "WEBSITE")
  assert_eq(rules[0].status, "DISABLED")
  assert_eq(rules[0].forced_replacement, "TXT")
}
