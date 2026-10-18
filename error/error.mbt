///|
/// COS 的错误形状。真 HTTP 读数只进 `Service` 那一臂，本地拒掉的走其它臂——
/// 把"没连上"和"服务端答了但拒绝"混成一个整数，重试策略就会被带偏（同 moon-s3／moon-oss 的理由）。
pub(all) struct ServiceError {
  status : Int32
  /// 响应体 `<Error><Code>` 的读数；读不出时是空串（HEAD 那一档可能就是空，见 `cos` 包的判不存在）
  code : String
  message : String
  /// `x-cos-request-id`，报障时要的那串
  request_id : String?
  /// `<TraceId>`：S3 没有这一位，COS 有。是否总在场未证，读不出就是空串
  trace_id : String
}

///|
pub(all) suberror CosError {
  BadParam(String)
  Network(String)
  /// 2xx 但回包缺必需字段：与"网络断"分开，与"服务端拒绝"也分开
  BadResponse(String)
  Service(ServiceError)
}

///|
/// 一行读数，供错误串与测试输出用。**不含**任何凭据。
pub fn CosError::text(self : CosError) -> String {
  match self {
    BadParam(m) => "cos bad-param: " + m
    Network(m) => "cos network: " + m
    BadResponse(m) => "cos bad-response: " + m
    Service(details) => {
      let head = details.status.to_string() + " " + details.code
      head + ": " + details.message
    }
  }
}
