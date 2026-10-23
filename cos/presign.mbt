///|
/// 预签名 URL。机制与隔壁两个 SDK 不同：不是换一套参数名，而是把 `Authorization` 的
/// 七个字段整体搬进 query（`auth/presign.mbt` 那侧负责搬与转义），所以这一族**没有**
/// `X-Amz-Expires` 那样的独立有效期参数——时间窗就写在 `q-sign-time` 的 `start;end` 里。
///
/// 默认把 `Host` 算进签名，所以**签名用的域名必须与访问域名同一个**：换成 CDN／自定义域
/// 那条 URL 当场就废（这一档在真桶上的边界属实测 M4／M5，本模块不提供跨域签名）。

///|
/// 免凭据下载 URL。签好之后**任何**持有它的人都能取，有效期是唯一的控制面。
/// 上限没有文档数字（实测 M3），本函数不自创一个顶，只拒"窗口不成立"。
pub fn Client::presigned_get_url(
  self : Client,
  bucket : String,
  key : String,
  expires_sec~ : Int64 = 600L,
) -> String raise @error.CosError {
  self.presigned_url("GET", bucket, key~, expires_sec~)
}

///|
/// 前端直传 URL。`content_type~` 一旦给定就要**原样**随上传发出：它参与了签名，
/// 直传方换个值发出去就是签名不符。不给这一项时 URL 不锁 Content-Type。
pub fn Client::presigned_put_url(
  self : Client,
  bucket : String,
  key : String,
  expires_sec~ : Int64 = 600L,
  content_type~ : String = "",
) -> String raise @error.CosError {
  let headers : Array[(String, String)] = if content_type.is_empty() {
    []
  } else {
    [("content-type", content_type)]
  }
  self.presigned_url("PUT", bucket, key~, expires_sec~, headers~)
}

///|
/// 本文件唯一读时钟的那一处。要钉住某个时刻就直接调 `@auth.presign_query`——
/// 时钟进签名是 auth 那层的能力，不该在业务面重做一遍。
fn Client::presigned_url(
  self : Client,
  verb : String,
  bucket : String,
  key~ : String = "",
  expires_sec~ : Int64 = 600L,
  headers~ : Array[(String, String)] = [],
  query~ : Array[(String, String)] = [],
) -> String raise @error.CosError {
  let config = self.config
  // STS 令牌走查询串，并且要参与 `q-sign-*` 的签名（官方预签名把 token 放 query）。
  let query = match config.credentials().security_token() {
    Some(token) => query + [("x-cos-security-token", token)]
    None => query
  }
  let host = config.host(bucket)
  let window = @auth.window_at(@auth.now_millis(), expires_sec)
  let signed = @auth.presign_query(
    config.credentials(),
    @auth.RequestToSign::{
      verb,
      path: @config.path_of(key),
      query,
      headers: [("host", host)] + headers,
    },
    window,
  )
  let base = config.scheme() + "://" + host + "/" + @config.encode_key(key)
  let extra = wire_query(query)
  let tail = if extra.is_empty() { signed } else { signed + "&" + extra }
  base + "?" + tail
}
