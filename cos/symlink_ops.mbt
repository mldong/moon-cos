///|
/// 软链接：`PUT/GET /<key>?symlink`。官方 Python SDK `put_symlink`/`get_symlink`
/// （`cos_client.py:5601-5680`，2026-10-22 现读）：目标写在 `x-cos-symlink-target` 头里，
/// 读侧也从同一个头回。链接对象不占数据体，删链接不删目标。
pub(all) struct SymlinkInfo {
  target : String?
  etag : String?
  version_id : String?
}

///|
pub async fn Client::put_symlink(
  self : Client,
  bucket : String,
  key : String,
  target : String,
  forbid_overwrite~ : Bool = false,
  storage_class~ : String = "",
  acl~ : String = "",
) -> Unit raise @error.CosError {
  if target.is_empty() {
    raise @error.BadParam("put_symlink needs a target key")
  }
  let response = request(
    self,
    "PUT",
    bucket~,
    key~,
    query=[("symlink", "")],
    headers=symlink_headers(target, forbid_overwrite~, storage_class~, acl~),
  )
  discard_body(response)
}

///|
pub async fn Client::get_symlink(
  self : Client,
  bucket : String,
  key : String,
) -> SymlinkInfo raise @error.CosError {
  let response = request(self, "GET", bucket~, key~, query=[("symlink", "")])
  discard_body(response)
  SymlinkInfo::{
    target: header_of(response.headers, "x-cos-symlink-target"),
    etag: header_of(response.headers, "etag"),
    version_id: header_of(response.headers, "x-cos-version-id"),
  }
}

///|
pub fn symlink_headers(
  target : String,
  forbid_overwrite~ : Bool = false,
  storage_class~ : String = "",
  acl~ : String = "",
) -> Array[(String, String)] {
  let headers : Array[(String, String)] = [("x-cos-symlink-target", target)]
  if forbid_overwrite {
    headers.push(("x-cos-forbid-overwrite", "true"))
  }
  if !storage_class.is_empty() {
    headers.push(("x-cos-storage-class", storage_class))
  }
  if !acl.is_empty() {
    headers.push(("x-cos-acl", acl))
  }
  headers
}
