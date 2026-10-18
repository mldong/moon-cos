///|
/// 错误文案这条纪律的用例：预签名 URL 的 query 是凭据本体，任何把它带进错误串的通道
/// 都要在出本库之前被隐去。参照实现对 `InvalidRequest` 的三档文案是**原样嵌 url** 的
/// （`url 缺 :// 分隔`、`url 带 fragment`、`pathless query`），所以这一档不是假想敌。

///|
test "问号之后一律隐去：q-ak 与签名不出现在错误串里" {
  let leaky = "url 缺 :// 分隔：https://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com/k.txt?q-sign-algorithm=sha1&q-ak=AKIDtestid00000000000000000000&q-signature=deadbeefdeadbeefdeadbeefdeadbeefdead"
  let folded = redact_query(leaky)
  assert_true(folded.find("q-ak") is None)
  assert_true(folded.find("q-signature") is None)
  assert_true(folded.find("AKIDtestid") is None)
  assert_true(
    folded.has_prefix(
      "url 缺 :// 分隔：https://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com/k.txt?<redacted>",
    ),
  )
}

///|
test "建连失败那一档本来只到源站，隐去这步不该动它一个字" {
  let detail = "建连失败（https://examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com）：TlsError"
  assert_eq(redact_query(detail), detail)
  assert_eq(
    transport_text(@transport.TransportError::Network(detail)),
    "network: " + detail,
  )
  assert_eq(transport_text(@transport.TransportError::Timeout), "timeout")
}
