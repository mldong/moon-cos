///|
/// 对象级 ACL 两条。写侧 `PUT /<key>?acl` + 头 `x-cos-acl`，读侧 `GET /<key>?acl` 回
/// `AccessControlPolicy/AccessControlList/Grant`——根元素与 S3 同名，但**匿名公有的身份写法**
/// 是本家的一套：Grantee 的 ID 是 `qcs::cam::anyone:anyone`，URI 是
/// `http://cam.qcloud.com/groups/global/AllUsers`。判"这一档是不是公有读"要认这两个身份，
/// 认 S3 那个 `AllUsers` URI 在这一族里恰好也能命中，认 ID 那一档只有本家给得出。
///
/// 头的 `x-cos-acl` 与 body 的 XML **二选一**（参照实现明确说同时给会冲突），
/// 所以这里只发头。

///|
pub(all) struct ObjectAcl {
  /// 每一档 `<Grant>` 的 permission 读数：`READ`／`WRITE`／`READ_ACP`／`WRITE_ACP`／`FULL_CONTROL`
  permissions : Array[String]
  /// 命中匿名身份且给到 READ 或 FULL_CONTROL
  public_read : Bool
  owner_id : String?
  body : String
}

///|
pub async fn Client::put_object_acl(
  self : Client,
  bucket : String,
  key : String,
  acl : CannedAcl,
) -> Unit raise @error.CosError {
  let response = request(self, "PUT", bucket~, key~, query=[("acl", "")], headers=[
    ("x-cos-acl", acl.text()),
  ])
  discard_body(response)
}

///|
pub async fn Client::get_object_acl(
  self : Client,
  bucket : String,
  key : String,
) -> ObjectAcl raise @error.CosError {
  let response = request(self, "GET", bucket~, key~, query=[("acl", "")])
  let body = response_body_text(response.body, response.status)
  parse_acl(body)
}

///|
pub async fn Client::put_bucket_acl(
  self : Client,
  bucket : String,
  acl : CannedAcl,
) -> Unit raise @error.CosError {
  let response = request(self, "PUT", bucket~, query=[("acl", "")], headers=[
    ("x-cos-acl", acl.text()),
  ])
  discard_body(response)
}

///|
pub async fn Client::get_bucket_acl(
  self : Client,
  bucket : String,
) -> ObjectAcl raise @error.CosError {
  let response = request(self, "GET", bucket~, query=[("acl", "")])
  let body = response_body_text(response.body, response.status)
  parse_acl(body)
}

///|
fn parse_acl(body : String) -> ObjectAcl {
  let permissions : Array[String] = []
  let mut public_read = false
  for section in xml_sections(body, "Grant") {
    let permission = or_empty(xml_first(section, "Permission"))
    permissions.push(permission)
    let anonymous = section.find("qcs::cam::anyone:anyone") is Some(_) ||
      section.find("cam.qcloud.com/groups/global/AllUsers") is Some(_)
    if anonymous && (permission == "READ" || permission == "FULL_CONTROL") {
      public_read = true
    }
  }
  ObjectAcl::{
    permissions,
    public_read,
    owner_id: xml_first(body, "ID"),
    body,
  }
}
