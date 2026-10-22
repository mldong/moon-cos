///|
/// COS 的读数形状。刻意做窄：只带文件存储契约真要用的字段。协议响应头还有二十几项，
/// 全抄进来就等于承诺维护一份与协议同宽的面——`x-cos-hash-crc64ecma` 这一类也一样，
/// 原生给得到，本模块这一轮不把它端上公开面。

///|
pub(all) struct PutObjectResult {
  etag : String
}

///|
pub(all) struct ObjectData {
  content_length : Int64
  content_type : String?
  /// 只回 `x-cos-meta-*` 那几项（键名已去掉前缀），与 `metadata~` 入参同一坐标系
  metadata : Array[(String, String)]
  content_range : String?
  etag : String?
  body : Bytes
}

///|
pub(all) struct ObjectInfo {
  key : String
  etag : String?
  size : Int64
  last_modified : String?
  storage_class : String?
}

///|
/// `HEAD /<key>` 的读数。与列举行那一格分开定：这一族要带元数据与 content-type，
/// 而列举回包里没有它们。
pub(all) struct ObjectStat {
  key : String
  etag : String?
  size : Int64
  last_modified : String?
  content_type : String?
  storage_class : String?
  metadata : Array[(String, String)]
}

///|
/// 列举一页。COS 原生**只有 V1 形态**（`marker`／`NextMarker`，没有 `list-type=2`），
/// 所以翻页游标就叫 `next_marker`，与隔壁 `moon-s3` 的 V2 那一格不同名。
pub(all) struct ObjectListing {
  objects : Array[ObjectInfo]
  /// `delimiter` 折叠出来的"目录"，与 objects 同一次回包、同一坐标系
  common_prefixes : Array[String]
  is_truncated : Bool
  next_marker : String?
  /// 请求里带没带 `encoding-type=url`：回包里的键是编码态还是原样，全看这一格
  encoding_type : String?
  /// 回包原文。解析件只取简单形状，读不出的形状要能回查
  body : String
}

///|
pub(all) struct CopyResult {
  etag : String
  body : String
}

///|
/// 批量删除里单条失败。成功与失败按 `<Deleted>` / `<Error>` 两族分开收。
pub(all) struct DeleteObjectFailure {
  key : String
  code : String
  message : String
}

///|
/// `POST /?delete` 的读数。`quiet=true` 时服务端可以不回正文。
pub(all) struct DeleteObjectsResult {
  deleted : Array[String]
  errors : Array[DeleteObjectFailure]
  body : String
}

///|
/// `UploadPartCopy` 的读数。ETag 优先取 XML，回包没有 XML 时退回响应头。
pub(all) struct UploadPartCopyResult {
  etag : String
  last_modified : String?
  body : String
}

///|
/// 一条未完成的分片任务。
pub(all) struct MultipartUploadInfo {
  key : String
  upload_id : String
  initiated : String?
}

///|
/// `GET /?uploads` 的一页。`next_*` 为空表示没有下一页。
pub(all) struct MultipartUploadListing {
  uploads : Array[MultipartUploadInfo]
  common_prefixes : Array[String]
  is_truncated : Bool
  next_key_marker : String?
  next_upload_id_marker : String?
  body : String
}

///|
/// 对象标签的一对键值。COS 上限 10 对，键在对象内唯一。
pub(all) struct ObjectTag {
  key : String
  value : String
}

///|
/// `GET /<key>?tagging` 的读数。
pub(all) struct ObjectTagging {
  tags : Array[ObjectTag]
  body : String
}

///|
/// `POST /<key>?append&position=N` 的读数。
pub(all) struct AppendResult {
  next_position : Int64?
  etag : String?
  body : String
}

///|
/// `PUT /<key>?acl` 的接受档。原生词汇与 S3 同族：`private`／`public-read`／
/// `public-read-write`，对象另多一档 `default`（继承桶权限，也是对象的默认值）。
/// `readonly` 那一族是**已弃用的 JSON API** 的词，XML API 不收，别照二手资料抄。
pub(all) enum CannedAcl {
  Default
  Private
  PublicRead
  PublicReadWrite
}

///|
pub fn CannedAcl::text(self : CannedAcl) -> String {
  match self {
    Default => "default"
    Private => "private"
    PublicRead => "public-read"
    PublicReadWrite => "public-read-write"
  }
}
