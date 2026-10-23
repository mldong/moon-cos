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
