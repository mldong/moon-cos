///|
/// 预签名＝把 `Authorization` 的七个字段**整体搬进 query**（参数名同名），不是换一套
/// 参数名。值再走一次百分号编码，于是窗口与两个 list 里的 `;` 变成 `%3B`——服务端解一次
/// 就还原成签名时那串，参照实现（Python `get_presigned_url`）同样是"拆开后 urlencode"。
///
/// 有效期靠 `q-sign-time` 的 `start;end` 自述，**没有** `X-Amz-Expires` 那样的独立参数；
/// 上限没有文档数字（阶段 H 卡 §2.4 的 M3），所以这里不自创一个顶，只拒"窗口本身不成立"。
///
/// 只做"拆开七个字段"这一种形态：Python 那份明确拒绝把七个字段合并进单个 `sign=` 的旧形态
/// （`fusion-io gateway only accepts split q-sign-* query parameters`）。
pub fn presign_query(
  credentials : Credentials,
  request : RequestToSign,
  window : Window,
  sign_host~ : Bool = true,
) -> String raise @error.CosError {
  if window.end <= window.start {
    raise @error.CosError::BadParam("presigned window must end after it starts")
  }
  let authorization = authorization(credentials, request, window, sign_host~)
  let parts : Array[String] = []
  for field in authorization.split("&") {
    let text = field.to_owned()
    match text.find("=") {
      None =>
        raise @error.CosError::BadResponse(
          "authorization field carries no value: " + text,
        )
      Some(at) => {
        let key = text[0:at].to_owned()
        let value = text[at + 1:].to_owned()
        parts.push(cos_encode(key) + "=" + cos_encode(value))
      }
    }
  }
  parts.join("&")
}
