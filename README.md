# mldong/moon-cos

腾讯云对象存储（COS）**原生协议**客户端的 MoonBit 版：签名是官方那套 `q-sign-*`（HMAC-SHA1
五步），寻址只有虚主机一种，族覆盖对象读写与删除、条件读、单层列举、同平台复制、手动分片五步、
预签名 GET 与 PUT、对象级 canned ACL、服务级列桶。

这不是"把 S3 兼容层换个端点"：兼容层那一侧的形状与读数是 `mldong/moon-s3` 的事，本仓全程走原生
XML API（`x-cos-*` 头族、`q-sign-*` 查询串、`x-cos-copy-source`），两边结论互不背书。
传输层是注入的端口：`Client` 收的是 `mldong/moon-hutool/http` 那个 `Transport` 端口，
碰网络的那半是它的 `AsyncHttpTransport`（异步跑在 `moonbitlang/async` 上）；本仓不认识任何
上层的数据结构，也不自带 HTTP 客户端。

## 最小用法

```moonbit
fn refused(f : () -> Unit raise @coserr.CosError) -> String {
  try {
    f()
    "no-error"
  } catch {
    @coserr.CosError::BadParam(_) => "BadParam"
    _ => "other"
  }
}

test "签名、URL 与边界都在本地算得出，这一块不打网络" {
  let id = "AKIDtestid00000000000000000000"
  let secret = "testSecretKey0123456789abcdef"
  let bucket = "examplebucket-1250000000"
  let host = "examplebucket-1250000000.cos.ap-guangzhou.myqcloud.com"
  let credentials = @cosauth.Credentials::new(id, secret)
  let config = @cosconfig.Config::new("ap-guangzhou", credentials)
  // 桶名是长命名 `<Name>-<APPID>`：appid 就在桶名里，本 SDK 没有另一个 appid 配置项。
  // 形状不对本地就响亮拒绝，不拿它换服务端一句照样应答的 NoSuchBucket。
  assert_eq(config.host(bucket), host)
  assert_eq(refused(() => @cosconfig.validate_bucket("no-appid-here")), "BadParam")
  // 能力位：对象预设 ACL 的字面量。`default` 是对象的默认值（继承桶权限）
  assert_eq(@sdk.CannedAcl::Default.text(), "default")
  assert_eq(@sdk.CannedAcl::PublicRead.text(), "public-read")
  // 签的那一串与发的那一串本来就该不同形：签名里是解码态 path，请求行里逐段编码、斜杠保留
  let tricky = "moonfs/a b+c.txt"
  assert_eq(@cosconfig.path_of(tricky), "/moonfs/a b+c.txt")
  assert_eq(@cosconfig.encode_key(tricky), "moonfs/a%20b%2Bc.txt")
  // Authorization 的七个字段：算法恒 `sha1`（`sha256` 那一档实测被端点 403 拒收），
  // 空值参数写成 `acl=`（带等号），键名先编码再整体小写
  let signed = @cosauth.authorization(
    credentials,
    @cosauth.RequestToSign::{
      verb: "GET",
      path: "/note.txt",
      query: [("acl", "")],
      headers: [("host", host)],
    },
    @cosauth.window_at(1760000000000L, 600L),
  )
  assert_true(signed.has_prefix("q-sign-algorithm=sha1&q-ak=" + id))
  assert_true(signed.contains("&q-header-list=host&q-url-param-list=acl"))
  assert_true(signed.find(secret) is None)
  // `sign_host=false` 那一档（现在只在 auth 层）：Host 退出签名，两个 list 为空仍要写出来
  let no_host = @cosauth.authorization(
    credentials,
    @cosauth.RequestToSign::{
      verb: "GET",
      path: "/note.txt",
      query: [],
      headers: [("host", host)],
    },
    @cosauth.window_at(1760000000000L, 600L),
    sign_host=false,
  )
  assert_true(no_host.contains("&q-header-list=&q-url-param-list=&q-signature="))
  // 预签名＝把同一批字段整体搬进 query：时间窗写在 `q-sign-time` 的 `start;end` 里，
  // 没有 `X-Amz-Expires` 那样的独立参数。URL 由虚主机派生，签名里也带着那个 Host
  let client = @sdk.Client::new(config, @transport.AsyncHttpTransport::new())
  let url = client.presigned_get_url(bucket, "moonfs/note.txt", expires_sec=600L)
  assert_true(url.has_prefix("https://" + host + "/"))
  assert_true(url.contains("/moonfs/note.txt?q-sign-algorithm=sha1&"))
  assert_true(url.contains("q-sign-time="))
  // 窗口不成立就在本地拒掉，不必发出去换一句 403；上限不设（文档没数字、端点那档未测）
  let gone = @cosauth.window_at(1760000000000L, -120L)
  assert_eq(
    refused(() => {
      let _ = @cosauth.presign_query(
        credentials,
        @cosauth.RequestToSign::{
          verb: "GET",
          path: "/note.txt",
          query: [],
          headers: [],
        },
        gone,
      )
    }),
    "BadParam",
  )
  // 604801 秒照签：起始时刻往前回拨 60 秒、结束时刻是 `now + expires`，本仓不自创一个顶
  assert_eq(@cosauth.window_at(1760000000000L, 604801L).text(), "1759999940;1760604801")
}
```

时刻是入参而不是内部取 `now()`（`window_at(millis, expires)`、`auth` 层那几个件都收）：这样"请求→
签名"整条链能被钉成一份可复现的样本，出问题时分得清是签名算错还是时钟漂移。
走 `Client` 的那些方法才自己读时钟：一次 API 请求算一个 3600 秒的窗口，预签名两条按给的
`expires_sec` 各算一个，除此之外没有第二处读钟的地方。

`secret_key` 是 `priv` 字段，公开出口没有任何一条回得去（上面那条 `find(secret) is None` 就是钉这个）；
错误串里 URL 问号之后一律隐去——预签名串的 query **就是**凭据本体（`q-ak` 加一条窗口内可用的签名），
日志里出现一次等于把那条授权多发一份。

## 装法

```bash
moon add mldong/moon-cos
```

版本 pin 由注册表解析（`moon add` 不给版本号），发上去的每一代就是 `moon.mod` 里那个 `version`。
本仓是**一个仓＝一个模块**：`auth`／`config`／`cos`／`error` 四个包同属 `mldong/moon-cos`，
一起发、一起装。模块还没上注册表之前（首推那一版之前），把本仓目录作为 workspace member 指过去就能引，
`scripts/readme-check.sh` 走的正是这条路——它把上面这块代码逐字抽出来、灌进一个空工程真编译真跑。

## 用之前要知道的几件事

- **只有虚主机，没有开关**。host 是 `<桶名>.cos.<区域>.myqcloud.com`，path 里只放对象键。
  path 风格在真桶上回 403（那条读数取自 S3 兼容层那一侧的探针，码是 `PathStyleDomainForbidden`，
  而且**只有状态码、没有正文**）；原生这一侧本来就没有 path 风格这条出口，所以也不做成配置项。
- **签名默认把 `Host` 算进去**，所以预签名 URL 绑定它被签时的那个域名：拿虚主机那条串换到自定义域名上
  取实测 403。要在自定义域名上出 URL，就用 `Config::with_domain` 造这一档的客户端——它签的就是那个
  域名的 Host，实测免凭据取回 **200、34 字节逐字相同**。（`@cosauth.presign_query(..., sign_host=false)`
  那一档仍在 `auth` 层：不绑 Host 的签名跨域名可用，但公开面没端出去，因为上面那条路已经够。）
- **scheme 是一个配置项，两档都能定**：`with_domain("http://<域名>", region, creds)` 与
  `with_domain("<域名>", region, creds, scheme="http")` 是同一条路的两种写法；两处都写时必须写同一
  意思，打架就地 `BadParam`——让后写的那一处悄悄赢，等于把"这一发走不走明文"埋进调用顺序里。
  都没写才落 `https`。区域端点那一档同样接 `scheme~`，给代理／内网镜像／抓包用，接真桶没有理由用它。
  真桶读数：域名档走 http 时对象族与同桶复制全过；同一域名换 `https` 卡在 TLS（证书是
  `CN=*.cos.<区域>.myqcloud.com`，SAN 不覆盖自定义域名，读数 `目标主要名称不正确`）——**那是桶侧没绑
  证书，不是签名问题**，绑上之后改走 https 不用动代码。签名不含 scheme，换档也不动签名面。
  这一档里 host 逐字用域名、**绝不拼桶名**（`<桶名>.<域名>` 连 DNS 都不解析），所以
  跨桶复制的源永远走 `canonical_host` 那条区域虚主机形。
- **只实现 `sha1`，且不提供 `sha256`**：`q-sign-algorithm=sha256` 在真桶上实测 **403 拒收**，
  三份官方参照实现也都把算法写死 sha1。没有正面读数的档位不进公开面。
- **签的串与发的串本来不同形**：签名里是**解码态** path 与"先编码再整体小写"的键名；请求行里是逐段编码
  后的键与驼峰的 `partNumber`／`uploadId`；空值参数在签名里写 `acl=`（等号不能省）。
  键里带中文、空格、`%`、`+`、`&` 的对象在真桶上写得进、读得回、也列得出（两处形态各按各自的规则）。
  照 AWS SigV4 或 OSS V4 的习惯抄会全线 403。
- **预签名没有有效期上限**：上限既没有文档数字、服务端那一档也未测，`604801` 秒在本地照签。
  本 SDK 因此不自创一个顶，只拒"窗口结束不晚于开始"。判"已过期"在 COS **不是独立 Code**——
  读数是一句 403 `AccessDenied`，正文里带 `Request has expired`，别按 Code 白名单写死。
- **区域不进签名**：填错区域错在 host 上，那一发实测 **404 且正文没有 `<Code>`**。
  签名里没有区域这一位，所以别指望签名层帮你发现它。
- **判"不存在"只看状态码**：`HEAD` 打不存在的键回 **404 且没有任何 XML 正文**（`TraceId` 也不在场），
  `stat_object` 抛出的 `Service` 里 `code` 可能是空串。
- **列举是 V1**：原生文档的参数表里没有 `list-type`，游标只有 `marker`／`NextMarker` 这一对，
  翻页字段因此就叫 `next_marker`（数据面对 `?list-type=2` 的实际反应是另一档读数，本 SDK 不发它）。
  每次列举**都带 `encoding-type=url`** 并把回包的键／前缀／游标解**一次**百分号，两侧坐标系与
  `put_object` 的 `key` 一致；解码走 lossy 档，解不动就原样保留，`ObjectListing.body` 随时可回查。
- **分片下限是 1 MiB，最后一片除外**：非尾片给 540672 字节那一发实测红在 complete 的
  `400 EntityTooSmall` 上（本仓自己踩过一次，之后每条腿都断"每片真到 1048576"）；
  翻点是在兼容层探针上量齐的——786432 红、1048576 过、尾片 1 B 过。
  `upload_part` 回的 ETag 是**带引号原样**，完成件要写回同一串。
  完成后的 ETag 带引号并带 `-N` 后缀（两片那一发读到的就是 `…-2` 这个形状），
  它不是整份对象的 MD5，本仓原样带回、不剥后缀、不拿它当校验依据。片号也不在本地校验，范围归服务端；
  `abort` 之后再查那一串片号回 **404**。
- **complete 不发 `Content-MD5`**：文档摘要里那句"required"在真桶上不成立——不发也收下来、
  对象尺寸对得上。
- **用户元数据只有 `x-cos-meta-*` 这一族**：`metadata~` 的键名**不带**前缀，写侧加、读侧剥，
  两侧同一坐标系（写了能读回）。
- **对象级 canned ACL 实测两档能用**：`private` 与 `public-read`（写 `public-read` 后匿名 GET 真取回，
  改回 `private` 即拒），`default` 是对象默认值＝继承桶权限；`public-read-write` 回 **400
  `InvalidArgument`**（服务端原文把 `invalid` 拼错了，照原样记）。SDK 只在 `set_acl=true` 时才发
  `x-cos-acl`：参照实现对"没指定 ACL"的姿势是不发头，多发一行既改签名也改服务端行为。
  读回侧判"是不是公有读"认的是本家那两个匿名身份（`qcs::cam::anyone:anyone`／
  `cam.qcloud.com/groups/global/AllUsers`）。
- **不发多值同名参数**：同名键多值送上去实测 **403 `SignatureDoesNotMatch`**。
  auth 层的规范化能吃重复键（向量档钉着"每个值重复出现一次键名"），但 SDK 自己一条都不发。
- **错密钥拒在签名上**：换错 SK 那一发实测 403 `SignatureDoesNotMatch`；改动预签名 URL 里摘要的
  一位也是 403。两条负判据各自独立成立。
- **2xx 且不需要正文的响应一律读尽再关**：传输层的连接池只收"读尽的线"，不读也不关等于把一条 TLS
  连接晾在外面，后面的请求会整等 30 秒再报 timeout（隔壁 `moon-oss` 真桶实测过的教训，这条纪律照带）。
- **这一代没有的东西**：没有 STS 临时凭据（`Credentials` 只有永久密钥两把，
  `x-cos-security-token` 那族靠前缀自动入签，本仓不提供注入点）；没有"一条式自动切分片"的
  大文件上传，分片由调用侧按五步走；没有上传进度回调。桶 CRUD、批量删除、标签、条件请求、
  CRC64 读回、软链接与桶配置族已端上公开面，真桶读数与未验证项见 [PARITY.md](PARITY.md)。

## 开发进度

状态词：**已实现**（有公开件且真桶跑过）、**部分实现**（子集真桶跑过，其余只有离线件）、
**待开发**（公开面里零命中）、**不适用**（协议里没这一族）。

| 能力 | 本 SDK 的件 | 状态 |
|---|---|---|
| 对象读写／删除／元数据 | `put_object` `get_object` `delete_object` `stat_object` | 已实现 |
| 列举／分片五步／预签名／对象 ACL | `list_objects`、分片五件、`presigned_*`、`put/get_object_acl` | 已实现 |
| 批量删除／对象标签／条件请求 | `delete_objects`、标签三件、`if_match~` 等 | 已实现 |
| 存储类／自动 MD5／CRC64 | `storage_class~`、`compute_md5~`、`object_crc64` | 已实现 |
| 追加写／软链接 | `append_object`、`put_symlink` `get_symlink` | 部分实现（软链接建链 403） |
| 归档解冻 | `restore_object` | 部分实现（仅离线件） |
| 桶基础 | `create_bucket` `delete_bucket` `bucket_exists` | 部分实现（建/删未跑真桶） |
| 桶配置读 | ACL／版本／CORS／标签／日志／网站／加密／生命周期／防盗链／策略／复制／清单／对象锁 | 部分实现（账号权限 403） |
| 桶配置写 | 上述各族的 `put_*` / `delete_*` | 部分实现（只有离线件） |
| STS／自动分片／进度回调 | 无对应件 | 待开发 |

完整对标台账：[PARITY.md](PARITY.md)。

## 许可

Apache-2.0。
