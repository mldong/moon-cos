///|
test "multipart uploads query omits empty filters" {
  let base = multipart_uploads_query(
    prefix="",
    delimiter="",
    max_uploads=1000,
    key_marker="",
    upload_id_marker="",
  )
  assert_eq(base.length(), 2)
  assert_eq(base[0].0, "uploads")
  assert_eq(base[1].0, "max-uploads")
  let full = multipart_uploads_query(
    prefix="p",
    delimiter="/",
    max_uploads=10,
    key_marker="k",
    upload_id_marker="u",
  )
  assert_eq(full.length(), 6)
  assert_eq(full[2].1, "p")
  assert_eq(full[3].1, "/")
  assert_eq(full[4].1, "k")
  assert_eq(full[5].1, "u")
}

///|
test "multipart upload listing parses uploads, prefixes and markers" {
  let body = "<ListMultipartUploadsResult><IsTruncated>true</IsTruncated><NextKeyMarker>k2</NextKeyMarker><NextUploadIdMarker>u2</NextUploadIdMarker><Upload><Key>a</Key><UploadId>u1</UploadId><Initiated>2026-10-22T00:00:00.000Z</Initiated></Upload><Upload><Key>b</Key><UploadId>u2</UploadId></Upload><CommonPrefixes><Prefix>dir/</Prefix></CommonPrefixes></ListMultipartUploadsResult>"
  let listing = parse_multipart_upload_listing(body)
  assert_eq(listing.uploads.length(), 2)
  assert_eq(listing.uploads[0].key, "a")
  assert_eq(listing.uploads[0].upload_id, "u1")
  assert_eq(listing.uploads[1].key, "b")
  assert_eq(listing.common_prefixes[0], "dir/")
  assert_eq(listing.is_truncated, true)
  match listing.next_key_marker {
    Some(value) => assert_eq(value, "k2")
    None => assert_true(false)
  }
  match listing.next_upload_id_marker {
    Some(value) => assert_eq(value, "u2")
    None => assert_true(false)
  }
}

///|
test "upload part copy prefers the XML etag" {
  let body = "<CopyPartResult><LastModified>2026-10-22T00:00:00.000Z</LastModified><ETag>\"abc\"</ETag></CopyPartResult>"
  let result = parse_upload_part_copy_result(body, [])
  assert_eq(result.etag, "\"abc\"")
  match result.last_modified {
    Some(value) => assert_eq(value, "2026-10-22T00:00:00.000Z")
    None => assert_true(false)
  }
}
