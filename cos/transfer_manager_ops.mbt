///|
/// 一次上传的续传状态。`parts` 里是已完成分片的 (号, ETag)。
pub(all) struct TransferState {
  upload_id : String
  offset : Int32
  parts : Array[(Int32, String)]
}

///|
/// 持有策略与状态的传输管理器：超过 `threshold` 自动分片、按 `part_size` 切片、
/// 每片回调 `progress`；失败后会话不 abort，状态留在对象里，下一次 `upload` 自动续传。
pub struct TransferManager {
  client : Client
  bucket : String
  part_size : Int32
  threshold : Int32
  progress : ((Int32, Int32) -> Unit)?
  slot : Array[TransferState]
}

///|
pub fn TransferManager::new(
  client : Client,
  bucket : String,
  part_size~ : Int32 = 8388608,
  threshold~ : Int32 = 8388608,
  progress~ : ((Int32, Int32) -> Unit)? = None,
) -> TransferManager {
  TransferManager::{
    client,
    bucket,
    part_size,
    threshold,
    progress,
    slot: [{ upload_id: "", offset: 0, parts: [], }],
  }
}

///|
/// 从外部持久化的状态恢复一个管理器。
pub fn TransferManager::restore(
  client : Client,
  bucket : String,
  state : TransferState,
  part_size~ : Int32 = 8388608,
  threshold~ : Int32 = 8388608,
  progress~ : ((Int32, Int32) -> Unit)? = None,
) -> TransferManager {
  TransferManager::{
    client,
    bucket,
    part_size,
    threshold,
    progress,
    slot: [state],
  }
}

///|
pub fn TransferManager::state(self : TransferManager) -> TransferState {
  self.slot[0]
}

///|
pub async fn TransferManager::upload(
  self : TransferManager,
  key : String,
  data : Bytes,
) -> ResumeUpload raise @error.CosError {
  let current = self.slot[0]
  let outcome = self.client.put_bytes_resumable(
    self.bucket,
    key,
    data,
    part_size=self.part_size,
    threshold=self.threshold,
    resume_upload_id=current.upload_id,
    resume_offset=current.offset,
    resume_parts=current.parts,
    progress=self.progress,
  )
  if outcome.error is Some(_) {
    self.slot[0] = TransferState::{
      upload_id: outcome.resume_upload_id,
      offset: outcome.resume_offset,
      parts: outcome.resume_parts,
    }
  } else {
    self.slot[0] = TransferState::{ upload_id: "", offset: 0, parts: [], }
  }
  outcome
}

///|
/// 分片下载：先 HEAD 取尺寸，超过 `chunk_size` 就按 Range 逐段取回再拼接。
/// 元数据取第一段的回包；`content_length` 用服务端总尺寸。
pub async fn TransferManager::download(
  self : TransferManager,
  key : String,
  chunk_size~ : Int32 = 8388608,
) -> ObjectData raise @error.CosError {
  if chunk_size <= 0 {
    raise @error.BadParam("chunk_size must be positive")
  }
  let head = self.client.stat_object(self.bucket, key)
  if head.size <= chunk_size.to_int64() || head.size <= 0L {
    return self.client.get_object(self.bucket, key)
  }
  let merged : Array[Byte] = []
  let mut first : ObjectData? = None
  let mut start = 0L
  while start < head.size {
    let end = if start + chunk_size.to_int64() < head.size {
      start + chunk_size.to_int64() - 1L
    } else {
      head.size - 1L
    }
    let part = self.client.get_object(
      self.bucket,
      key,
      range="bytes=" + start.to_string() + "-" + end.to_string(),
    )
    if first is None {
      first = Some(part)
    }
    merged.append(part.body.to_array())
    start = end + 1L
  }
  match first {
    None => self.client.get_object(self.bucket, key)
    Some(template) =>
      ObjectData::{
        content_length: head.size,
        content_type: template.content_type,
        metadata: template.metadata,
        content_range: None,
        etag: template.etag,
        body: Bytes::from_array(merged),
      }
  }
}

///|
/// 跨桶搬运：源对象不超过 `threshold` 走单发复制，否则在目标桶建分片任务、
/// 用 `upload_part_copy` 按 `part_size` 复制分片再合并。返回目标对象的 ETag。
pub async fn TransferManager::copy_to(
  self : TransferManager,
  source_key : String,
  dest_bucket : String,
  dest_key : String,
  threshold~ : Int32 = 8388608,
  part_size~ : Int32 = 8388608,
) -> String raise @error.CosError {
  if part_size <= 0 || threshold <= 0 {
    raise @error.BadParam("part_size and threshold must be positive")
  }
  let head = self.client.stat_object(self.bucket, source_key)
  if head.size <= threshold.to_int64() {
    let copied = self.client.copy_object(
      self.bucket,
      source_key,
      dest_bucket,
      dest_key,
    )
    return copied.etag
  }
  let upload_id = self.client.create_multipart_upload(dest_bucket, dest_key)
  let parts : Array[(Int32, String)] = []
  let mut start = 0L
  let mut number = 1
  while start < head.size {
    let end = if start + part_size.to_int64() < head.size {
      start + part_size.to_int64() - 1L
    } else {
      head.size - 1L
    }
    let outcome : Result[String, @error.CosError] = Ok(
      self.client.upload_part_copy(
        self.bucket,
        source_key,
        dest_bucket,
        dest_key,
        upload_id,
        number,
        copy_source_range="bytes=" + start.to_string() + "-" + end.to_string(),
      ).etag,
    ) catch {
      err => {
        let _ = self.client.abort_multipart_upload(
          dest_bucket, dest_key, upload_id,
        ) catch {
          _ => ()
        }
        Err(err)
      }
    }
    let etag = match outcome {
      Ok(value) => value
      Err(err) => raise err
    }
    parts.push((number, etag))
    number = number + 1
    start = end + 1L
  }
  let done = self.client.complete_multipart_upload(
    dest_bucket,
    dest_key,
    upload_id,
    parts~,
  )
  done.etag
}
