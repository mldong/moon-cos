///|
/// OSS 的响应体是 XML，但形状只有寥寥几种：`<Error>` 报告、列举的 `Contents` 行、
/// 分片的 `Part` 行、ACL 的 `Grant`。引一个完整 XML 解析器的代价大于收益，
/// 所以这里只给三件：取第一处、取每一处、按父标签切段。
///
/// 一条纪律：**读不到就是 `None`（或空数组），不静默给空值**。列举回包里少一个
/// `<Key>` 与"这个桶是空的"是两件事，混成一件就只能靠人肉看响应体。

///|
/// 按文档序取每一处 `<tag>…</tag>` 的内容。
pub fn xml_all(text : String, tag : String) -> Array[String] {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  let out : Array[String] = []
  let mut cursor = 0
  while cursor < text.length() {
    let rest = text[cursor:text.length()].to_owned()
    match rest.find(open) {
      None => cursor = text.length()
      Some(open_at) => {
        let value_start = cursor + open_at + open.length()
        let tail = text[value_start:text.length()].to_owned()
        match tail.find(close) {
          None => cursor = text.length()
          Some(close_at) => {
            let value = text[value_start:value_start + close_at].to_owned()
            out.push(xml_unescape(value))
            cursor = value_start + close_at + close.length()
          }
        }
      }
    }
  }
  out
}

///|
/// 只读第一处 `<tag>…</tag>`。
pub fn xml_first(text : String, tag : String) -> String? {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  match text.find(open) {
    None => None
    Some(start) => {
      let value_start = start + open.length()
      let tail = text[value_start:text.length()].to_owned()
      match tail.find(close) {
        None => None
        Some(offset) => {
          let end = value_start + offset
          Some(xml_unescape(text[value_start:end].to_owned()))
        }
      }
    }
  }
}

///|
/// 按父标签切段，返回每一段的**内部文本**。列举一行要同时读 `Key`／`Size`／`ETag`，
/// 先把段切出来再在段内取值，才不会把上一段的字段接到下一段上
/// （`xml_all("Key")` 与 `xml_all("Size")` 各取一次，长度不等时就是错配）。
pub fn xml_sections(text : String, tag : String) -> Array[String] {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  let out : Array[String] = []
  let mut cursor = 0
  while cursor < text.length() {
    let rest = text[cursor:text.length()].to_owned()
    match rest.find(open) {
      None => cursor = text.length()
      Some(open_at) => {
        let body_start = cursor + open_at + open.length()
        let tail = text[body_start:text.length()].to_owned()
        match tail.find(close) {
          None => cursor = text.length()
          Some(close_at) => {
            out.push(text[body_start:body_start + close_at].to_owned())
            cursor = body_start + close_at + close.length()
          }
        }
      }
    }
  }
  out
}

///|
/// 实体还原归 hutool（`@text.unescape_xml`），本仓不再自带那张表。
///
/// 两者对 S3/OSS 实际会回的形状逐字相同（ETag 的 `&#34;…&#34;`、键里的 `&`／`<`、
/// `&amp;lt;` 这类"解一趟就到位"的档位都同读数）；hutool 是**超集**——它还认十六进制引用与任意
/// 十进制引用，那是参照实现本来认的，多认不出错。
///
/// 唯一不追求逐字等价的一档：那一件是 `raise`，解不动时**整串原样退回**，
/// 不是逐 token 退回（本库负向用例钉着）。落单代理 `&#xD800;` 这类形状 MoonBit 的 `String`
/// 表示不了，整串拒绝比产出一个装不下的值诚实。
pub fn xml_unescape(text : String) -> String {
  @text.unescape_xml(text) catch {
    _ => text
  }
}

///|
/// 错误体里的 `<Code>`，读不出给空串（调用方按空串走"非服务端错"那一档）。
pub fn xml_error_code(body : String) -> String {
  match xml_first(body, "Code") {
    Some(code) => code
    None => ""
  }
}

///|
/// 写进 XML 请求体的文本要转义（对象键可以含 `&` 与 `<`）。同样归 hutool：
/// 它的 `escape_xml` 是单趟查表，不会像"逐条 replace_all"那样把刚产出的 `&amp;` 再吃进去。
pub fn xml_escape(text : String) -> String {
  @text.escape_xml(text)
}
