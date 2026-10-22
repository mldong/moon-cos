///|
/// 服务端加密：`GET/PUT/DELETE /?encryption`。只读回 `SSEAlgorithm`；未配置时 404 读成 `None`。
pub async fn Client::put_bucket_encryption(
  self : Client,
  bucket : String,
  algorithm~ : String = "AES256",
) -> Unit raise @error.CosError {
  if algorithm.is_empty() {
    raise @error.BadParam("encryption algorithm is required")
  }
  let document = encryption_document(algorithm)
  let response = request(
    self,
    "PUT",
    bucket~,
    query=[("encryption", "")],
    headers=[("content-type", "application/xml")],
    body=@transport.RequestBody::Bytes(@utf8.encode(document.view())),
  )
  discard_body(response)
}

///|
pub async fn Client::get_bucket_encryption(
  self : Client,
  bucket : String,
) -> String? raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("encryption", "")]) catch {
    err =>
      match err {
        @error.CosError::Service(details) =>
          if details.status == 404 {
            return None
          } else {
            raise err
          }
        _ => raise err
      }
  }
  let body = response_body_text(response.body, response.status)
  xml_first(body, "SSEAlgorithm")
}

///|
pub async fn Client::delete_bucket_encryption(
  self : Client,
  bucket : String,
) -> Unit raise @error.CosError {
  let response = request(self, "DELETE", bucket~, query=[("encryption", "")])
  discard_body(response)
}

///|
fn encryption_document(algorithm : String) -> String {
  "<ServerSideEncryptionConfiguration><Rule><ApplyServerSideEncryptionByDefault><SSEAlgorithm>" +
  xml_escape(algorithm) +
  "</SSEAlgorithm></ApplyServerSideEncryptionByDefault></Rule></ServerSideEncryptionConfiguration>"
}
