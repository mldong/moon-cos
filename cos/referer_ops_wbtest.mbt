///|
test "referer document writes the COS status, type and domain list" {
  let config = BucketReferer::{
    status: Some("Enabled"),
    referer_type: Some("White-List"),
    domains: ["*.qq.com", "*.qcloud.com"],
    empty_refer_configuration: Some("Allow"),
  }
  assert_eq(
    referer_document(config),
    "<RefererConfiguration><Status>Enabled</Status><RefererType>White-List</RefererType>" +
    "<DomainList><Domain>*.qq.com</Domain><Domain>*.qcloud.com</Domain></DomainList>" +
    "<EmptyReferConfiguration>Allow</EmptyReferConfiguration></RefererConfiguration>",
  )
}

///|
test "referer parse reads the COS shape" {
  let body = "<RefererConfiguration><Status>Enabled</Status><RefererType>Black-List</RefererType>" +
    "<DomainList><Domain>*.bad.example</Domain></DomainList>" +
    "<EmptyReferConfiguration>Deny</EmptyReferConfiguration></RefererConfiguration>"
  let config = parse_referer(body)
  assert_eq(config.status, Some("Enabled"))
  assert_eq(config.referer_type, Some("Black-List"))
  assert_eq(config.domains, ["*.bad.example"])
  assert_eq(config.empty_refer_configuration, Some("Deny"))
}

///|
test "referer parse tolerates an empty configuration" {
  let config = parse_referer("<RefererConfiguration></RefererConfiguration>")
  assert_eq(config.status, None)
  assert_eq(config.domains.length(), 0)
  let empty = BucketReferer::{
    status: None,
    referer_type: None,
    domains: [],
    empty_refer_configuration: None,
  }
  assert_eq(
    referer_document(empty),
    "<RefererConfiguration><DomainList></DomainList></RefererConfiguration>",
  )
}
