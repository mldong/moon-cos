///|
/// 可续传上传的最小形态：**不 abort 失败会话**，而是把 `upload_id` 与已完成分片
/// 编成一段文本交给调用方持久化；下次把同一段文本传回 `state~` 就从缺口继续。
/// 调用方持久化的是三个值：`resume_upload_id~`、`resume_offset~`、`resume_parts~`；
/// `state` 字段给出一段可打日志的快照（`<uploadId>|<offset>|<n>:<etag>,...`）。
pub(all) struct ResumeUpload {
  etag : String?
  state : String
  error : String?
}

///|
pub fn resume_state_text(
  upload_id : String,
  offset : Int32,
  parts : Array[(Int32, String)],
) -> String {
  let encoded : Array[String] = []
  for part in parts {
    encoded.push(part.0.to_string() + ":" + part.1)
  }
  upload_id + "|" + offset.to_string() + "|" + encoded.join(",")
}

///|
/// 一条式可续传上传。成功时 `state` 为空串；失败时返回已完成分片的 `state`
/// 与错误文案，且**不 abort** 会话，调用方可用同一状态再调一次。
pub async fn Client::put_bytes_resumable(
  self : Client,
  bucket : String,
  key : String,
  data : Bytes,
  part_size~ : Int32 = 8388608,
  threshold~ : Int32 = 8388608,
  content_type~ : String = "",
  resume_upload_id~ : String = "",
  resume_offset~ : Int32 = 0,
  resume_parts~ : Array[(Int32, String)] = [],
  progress~ : ((Int32, Int32) -> Unit)? = None,
) -> ResumeUpload raise @error.CosError {
  if part_size <= 0 || threshold <= 0 {
    raise @error.BadParam("part_size and threshold must be positive")
  }
  if part_size < 102400 {
    raise @error.BadParam("OSS part_size must be at least 102400 bytes")
  }
  if resume_upload_id.is_empty() && data.length() <= threshold {
    let put = self.put_object(bucket, key, data, content_type~)
    return ResumeUpload::{ etag: Some(put.etag), state: "", error: None, }
  }
  let mut upload_id = resume_upload_id
  let mut offset = resume_offset
  let parts = resume_parts
  if upload_id.is_empty() {
    upload_id = self.create_multipart_upload(bucket, key, content_type~)
  }
  while offset < data.length() {
    let end = if offset + part_size < data.length() {
      offset + part_size
    } else {
      data.length()
    }
    let number = parts.length() + 1
    let etag = self.upload_part(
      bucket,
      key,
      upload_id,
      number,
      data[offset:end].to_owned(),
    ) catch {
      err =>
        return ResumeUpload::{
          etag: None,
          state: resume_state_text(upload_id, offset, parts),
          error: Some(err.text()),
        }
    }
    parts.push((number, etag))
    offset = end
    match progress {
      Some(report) => report(offset, data.length())
      None => ()
    }
  }
  let done = self.complete_multipart_upload(bucket, key, upload_id, parts~) catch {
    err =>
      return ResumeUpload::{
        etag: None,
        state: resume_state_text(upload_id, offset, parts),
        error: Some(err.text()),
      }
  }
  ResumeUpload::{ etag: Some(done.etag), state: "", error: None, }
}
