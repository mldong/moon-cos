///|
test "crc64_xz matches the CRC-64/XZ check vector" {
  let check = crc64_xz(@utf8.encode("123456789"))
  assert_eq(check, 0x995DC9BBDF1939FA)
  assert_eq(crc64_decimal(check), "11051210869376104954")
  assert_eq(crc64_xz(Bytes::from_array([])), 0)
  assert_eq(crc64_decimal(0), "0")
}

///|
test "crc64 decimal formats the full 64-bit range" {
  assert_eq(crc64_decimal(10), "10")
  assert_eq(crc64_decimal(18446744073709551615), "18446744073709551615")
}
