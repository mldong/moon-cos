///|
test "tagging document escapes keys and values" {
  let document = tagging_document([
    ObjectTag::{ key: "a&b", value: "<v>", },
    ObjectTag::{ key: "k", value: "v", },
  ])
  assert_true(document.contains("<Key>a&amp;b</Key>"))
  assert_true(document.contains("<Value>&lt;v&gt;</Value>"))
}

///|
test "tagging parses tag sections and unescapes values" {
  let body = "<Tagging><TagSet><Tag><Key>a</Key><Value>1</Value></Tag><Tag><Key>b</Key><Value>x&amp;y</Value></Tag></TagSet></Tagging>"
  let tagging = parse_object_tagging(body)
  assert_eq(tagging.tags.length(), 2)
  assert_eq(tagging.tags[0].key, "a")
  assert_eq(tagging.tags[1].value, "x&y")
  assert_eq(tagging.body, body)
}

///|
test "tagging rejects more than ten tags" {
  let tags : Array[ObjectTag] = []
  for i in 0..<11 {
    tags.push(ObjectTag::{ key: "k" + i.to_string(), value: "v", })
  }
  let mut rejected = false
  check_tags(tags) catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}

///|
test "tagging rejects duplicate keys" {
  let mut rejected = false
  check_tags([
    ObjectTag::{ key: "same", value: "1", },
    ObjectTag::{ key: "same", value: "2", },
  ]) catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
