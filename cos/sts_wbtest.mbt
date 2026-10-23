///|
test "presigned URLs reject sts credentials instead of dropping the token" {
  let credentials = @auth.Credentials::new("id", "key").with_security_token(
    "token-1",
  )
  let config = @config.Config::new("ap-guangzhou", credentials)
  let client = Client::new(config, @transport.AsyncHttpTransport::new())
  let mut rejected = false
  let _ = client.presigned_get_url("b-1250000000", "k") catch {
    @error.CosError::BadParam(_) => {
      rejected = true
      ""
    }
    _ => ""
  }
  assert_true(rejected)
}
