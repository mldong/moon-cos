///|
test "replication document nests rules under Rules and writes role" {
  let config = ReplicationConfig::{
    role: "qcs::cam::uin/1000:uin/1000",
    rules: [ReplicationRule::new("r1", "dst-1250000000", prefix="img/")],
  }
  assert_eq(
    replication_document(config),
    "<ReplicationConfiguration><Role>qcs::cam::uin/1000:uin/1000</Role><Rules>" +
    "<Rule><ID>r1</ID><Prefix>img/</Prefix><Status>Enabled</Status>" +
    "<Destination><Bucket>dst-1250000000</Bucket></Destination></Rule>" +
    "</Rules></ReplicationConfiguration>",
  )
}

///|
test "replication parse reads role, destination and storage class" {
  let body = "<ReplicationConfiguration><Role>role</Role><Rules>" +
    "<Rule><ID>a</ID><Prefix></Prefix><Status>Enabled</Status>" +
    "<Destination><Bucket>dst</Bucket><StorageClass>STANDARD_IA</StorageClass></Destination>" +
    "</Rule></Rules></ReplicationConfiguration>"
  let config = parse_replication(body)
  assert_eq(config.role, "role")
  assert_eq(config.rules.length(), 1)
  assert_eq(config.rules[0].destination_bucket, "dst")
  assert_eq(config.rules[0].storage_class, "STANDARD_IA")
}
