///|
test "presigned URLs carry the sts token in the signed query" {
  let credentials = @auth.Credentials::new("id", "key").with_security_token(
    "token-1",
  )
  let config = @config.Config::new("ap-guangzhou", credentials)
  let client = Client::new(config, @transport.AsyncHttpTransport::new())
  let url = client.presigned_get_url("b-1250000000", "k") catch {
    _ => abort("presign must work with an sts token")
  }
  assert_true(url.contains("x-cos-security-token=token-1"))
}
