///|
/// 翻页器：按 `NextMarker` 把 [Client::list_objects] 翻到底。
/// `max_pages` 是防跑飞的硬上限（默认 1000 页）；回包的 `body` 留最后一页原文。
pub async fn Client::list_all_objects(
  self : Client,
  bucket : String,
  prefix~ : String = "",
  delimiter~ : String = "",
  max_keys~ : Int32 = 1000,
  max_pages~ : Int32 = 1000,
) -> ObjectListing raise @error.CosError {
  let objects : Array[ObjectInfo] = []
  let prefixes : Array[String] = []
  let mut marker = ""
  let mut pages = 0
  let mut body = ""
  let mut last_truncated = false
  let mut next_marker : String? = None
  while pages < max_pages {
    let page = self.list_objects(
      bucket,
      prefix~,
      delimiter~,
      marker~,
      max_keys~,
    )
    objects.append(page.objects)
    prefixes.append(page.common_prefixes)
    body = page.body
    last_truncated = page.is_truncated
    next_marker = page.next_marker
    pages = pages + 1
    match next_marker {
      None => break
      Some(next) =>
        if !page.is_truncated || next.is_empty() {
          break
        } else {
          marker = next
        }
    }
  }
  ObjectListing::{
    objects,
    common_prefixes: prefixes,
    is_truncated: last_truncated,
    next_marker,
    encoding_type: None,
    body,
  }
}
