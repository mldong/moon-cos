///|
fn tm_client() -> Client raise @error.CosError {
  let credentials = @auth.Credentials::new("id", "key")
  let config = @config.Config::new("ap-guangzhou", credentials)
  Client::new(config, @transport.AsyncHttpTransport::new())
}

///|
test "transfer manager seeds empty state and restores a given state" {
  let client = tm_client() catch { _ => abort("client must build") }
  let fresh = TransferManager::new(
    client,
    "b",
    part_size=1048576,
    threshold=1048576,
  )
  assert_eq(fresh.state().upload_id, "")
  let saved = TransferState::{
    upload_id: "upload-1",
    offset: 2097152,
    parts: [(1, "etag-a"), (2, "etag-b")],
  }
  let restored = TransferManager::restore(client, "b", saved)
  assert_eq(restored.state().upload_id, "upload-1")
  assert_eq(restored.state().offset, 2097152)
  assert_eq(restored.state().parts.length(), 2)
}
