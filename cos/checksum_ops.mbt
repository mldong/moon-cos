///|
/// 对象 CRC64。COS 的 `x-cos-hash-crc64ecma` 实测是 **CRC-64/XZ**：
/// 反射的 ECMA 多项式 `0xC96C5795D7870F42`、初值与终值异或都是全 1。
/// 2026-10-22 真桶对照：`"opts payload"` 的服务端读数 6288925745358736737
/// 与本实现逐位相同；非反射的 ECMA-182 读数对不上，所以别按名字里的 “ecma” 选实现。
pub fn crc64_xz(data : Bytes) -> UInt64 {
  let poly : UInt64 = 0xC96C5795D7870F42
  let all_ones : UInt64 = 0xFFFFFFFFFFFFFFFF
  let mut crc : UInt64 = all_ones
  for byte in data {
    crc = crc ^ byte.to_int().to_uint64()
    for _ in 0..<8 {
      if (crc & 1) != 0 {
        crc = (crc >> 1) ^ poly
      } else {
        crc = crc >> 1
      }
    }
  }
  crc ^ all_ones
}

///|
/// 服务端回的是十进制串，本地校验要按同一形状比。
pub fn crc64_decimal(value : UInt64) -> String {
  if value == 0 {
    return "0"
  }
  let ten : UInt64 = 10
  let digits : Array[Char] = []
  let mut rest = value
  while rest > 0 {
    let digit = (rest % ten).to_int()
    digits.push((digit + 48).to_char().unwrap())
    rest = rest / ten
  }
  let mut out = ""
  let mut i = digits.length()
  while i > 0 {
    i = i - 1
    out = out + digits[i].to_string()
  }
  out
}

///|
/// `HEAD /<key>` 读服务端的 CRC64 读数（`x-cos-hash-crc64ecma`）。
/// 没这个头就回 `None`：不是所有对象/存储类型都带它，缺席不等于 0。
pub async fn Client::object_crc64(
  self : Client,
  bucket : String,
  key : String,
) -> String? raise @error.CosError {
  let response = request(self, "HEAD", bucket~, key~)
  discard_body(response)
  header_of(response.headers, "x-cos-hash-crc64ecma")
}
