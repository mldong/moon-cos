///|
test "inventory document writes COSBucketDestination" {
  let config = InventoryConfig::{
    id: "weekly",
    is_enabled: true,
    format: "CSV",
    destination_bucket: "qcs::cos:ap-guangzhou::dst-1250000000",
    destination_prefix: "reports/",
    account_id: "100000000001",
    frequency: "Weekly",
    included_versions: "All",
    filter_prefix: "logs/",
    optional_fields: ["Size", "ETag"],
  }
  assert_eq(
    inventory_document(config),
    "<InventoryConfiguration><Id>weekly</Id><IsEnabled>true</IsEnabled>" +
    "<Destination><COSBucketDestination><Format>CSV</Format>" +
    "<AccountId>100000000001</AccountId>" +
    "<Bucket>qcs::cos:ap-guangzhou::dst-1250000000</Bucket><Prefix>reports/</Prefix>" +
    "</COSBucketDestination></Destination>" +
    "<Schedule><Frequency>Weekly</Frequency></Schedule>" +
    "<Filter><Prefix>logs/</Prefix></Filter>" +
    "<IncludedObjectVersions>All</IncludedObjectVersions>" +
    "<OptionalFields><Field>Size</Field><Field>ETag</Field></OptionalFields>" +
    "</InventoryConfiguration>",
  )
}

///|
test "inventory parse reads COS nested configuration" {
  let body = "<InventoryConfiguration><Id>weekly</Id><IsEnabled>false</IsEnabled>" +
    "<Destination><COSBucketDestination><Format>CSV</Format><Bucket>dst</Bucket>" +
    "<Prefix>p/</Prefix></COSBucketDestination></Destination>" +
    "<Schedule><Frequency>Daily</Frequency></Schedule>" +
    "<IncludedObjectVersions>Current</IncludedObjectVersions>" +
    "<OptionalFields><Field>Size</Field></OptionalFields></InventoryConfiguration>"
  let config = parse_inventory(body)
  assert_eq(config.id, "weekly")
  assert_eq(config.is_enabled, false)
  assert_eq(config.destination_bucket, "dst")
  assert_eq(config.filter_prefix, "")
  assert_eq(config.optional_fields, ["Size"])
}
