///|
test "bucket tagging does not impose the object 10-tag cap" {
  let tags : Array[ObjectTag] = []
  for i in 0..<11 {
    tags.push(ObjectTag::{ key: "k" + i.to_string(), value: "v", })
  }
  check_bucket_tags(tags)
}

///|
test "bucket tagging rejects duplicate keys" {
  let mut rejected = false
  check_bucket_tags([
    ObjectTag::{ key: "same", value: "1", },
    ObjectTag::{ key: "same", value: "2", },
  ]) catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
