# moon-cos · 官方 COS SDK 对标台账

> 协议基线：[COS API 文档](https://cloud.tencent.com/document/product/436/10111)
> 参考实现：`tencentyun/cos-python-sdk-v5@V1.9.44`（2026-05-29）；交叉核对 Go `v0.7.76`（2026-10-22）
> 本仓版本：`mldong/moon-cos@0.6.0`
> 当前公开面：69 个 `Client::` 方法（0.6.0）
> 状态：现有行先记 `已实现`，真桶证据待按基线逐行复核

## 1. 当前公开面

| ID | 能力族 | 官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|---|
| COS-OBJ-001 | 对象 CRUD | PUT / GET / HEAD / DELETE / PUT Copy | `put_object` `get_object` `stat_object` `delete_object` `copy_object` | P0 | 真桶已验证 | `cos/live_test.mbt`、`cos/live_probe_test.mbt`（2026-10-22 真桶绿） |
| COS-OBJ-002 | 列举 | GET Bucket（V1，marker/NextMarker） | `list_objects` | P0 | 真桶已验证 | `cos/live_test.mbt`（2026-10-22 真桶绿）；原生文档只列 V1 |
| COS-OBJ-003 | 批量删除 | DeleteMultipleObjects | `delete_objects` | P0 | 真桶已验证 | `cos/delete_ops_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 真桶绿） |
| COS-OBJ-005 | 对象标签 | Put/Get/DeleteObjectTagging | `put_object_tagging` `get_object_tagging` `delete_object_tagging` | P0 | 真桶已验证 | `cos/tagging_ops_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 真桶绿） |
| COS-OBJ-007 | 条件请求 | If-Match/If-None-Match + If-Modified-Since/If-Unmodified-Since + 复制源条件 | `put_object` `get_object` `stat_object` `delete_object` `copy_object` `upload_part_copy` 的可选参数 | P0 | 真桶已验证 | `cos/object_options_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 真桶绿） |
| COS-OBJ-014 | 校验和 | CRC64 读回（`x-cos-hash-crc64ecma`） | `crc64_xz` `crc64_decimal` `object_crc64` | P0 | 真桶已验证 | `cos/checksum_ops_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 与真桶头逐位相同） |
| COS-MPU-001 | 分片 | Initiate / UploadPart / ListParts / Complete / Abort | `create_multipart_upload` `upload_part` `list_parts` `complete_multipart_upload` `abort_multipart_upload` | P0 | 真桶已验证 | `cos/live_test.mbt`（2026-10-22 真桶绿） |
| COS-MPU-002 | 分片复制 | UploadPartCopy | `upload_part_copy` | P0 | 真桶已验证 | `cos/multipart_extra_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 真桶绿） |
| COS-MPU-003 | 未完成分片 | ListMultipartUploads | `list_multipart_uploads` | P0 | 真桶已验证 | `cos/multipart_extra_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22 真桶绿） |
| COS-PRE-001 | 预签名 | 查询串 `q-sign-*`（GET/PUT） | `presigned_get_url` `presigned_put_url` | P0 | 真桶已验证 | `cos/live_test.mbt`（2026-10-22 真桶绿） |
| COS-ACL-001 | 对象 ACL | GetObjectACL / PutObjectACL | `get_object_acl` `put_object_acl` | P0 | 真桶已验证 | `cos/live_test.mbt`（2026-10-22 真桶绿）；canned `private/public-read/public-read-write/default` |
| COS-BKT-001 | 服务级列举 | ListBuckets | `list_buckets` | P1 | 真桶已验证 | `cos/live_test.mbt`（2026-10-22 真桶绿） |
| COS-BKT-002 | 桶基础 | PutBucket / DeleteBucket / HeadBucket | `create_bucket` `delete_bucket` `bucket_exists` | P1 | 已实现 | `cos/bucket_admin_wbtest.mbt`；`bucket_exists` 2026-10-22 真桶绿（HEAD 403 回退 list）；建/删桶不跑真桶 |
| COS-BKT-003 | 桶 ACL | GetBucketACL / PutBucketACL | `get_bucket_acl` `put_bucket_acl` | P1 | 已实现 | `cos/acl_ops.mbt` 复用对象 ACL 解析；读真桶受账号权限 403，未验证 |
| COS-BKT-005 | 版本控制 | GetBucketVersioning / PutBucketVersioning | `get_bucket_versioning` `put_bucket_versioning` | P1 | 已实现 | `cos/versioning_ops_wbtest.mbt`；读真桶受账号权限 403，未验证 |
| COS-OBJ-012 | 归档解冻 | RestoreObject | `restore_object` | P1 | 已实现 | `cos/restore_ops_wbtest.mbt`；真桶待补（需归档对象） |
| COS-BKT-004 | CORS | Get/Put/DeleteBucketCORS | `get_bucket_cors` `put_bucket_cors` `delete_bucket_cors` | P1 | 已实现 | `cos/cors_ops_wbtest.mbt`；读真桶受账号权限 403，未验证 |

## 2. 缺口台账

### P0 · 数据面核心

| ID | 官方操作 | 我们的方法 | 状态 | 备注 |
|---|---|---|---|---|
| COS-OBJ-006 | x-cos-storage-class（存储类） | 写入 `put_object`/`copy_object`/`create_multipart_upload`；回读 `stat_object`/`list_objects` | 真桶已验证 | 2026-10-22 真桶绿；标准档 HEAD 省略该头，List 可读；`ObjectStat`/`ObjectInfo` 已加字段，需抬版本 |
| COS-OBJ-008 | Content-MD5 / CRC64 | `put_object` / `upload_part` 已收 `content_md5~` 或 `compute_md5~` | 实现中 | 自动 MD5 2026-10-22 真桶绿；CRC64 未公开 |

### P1 · 控制面与厂商数据面扩展

| ID | 能力/官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|
| COS-OBJ-009 | 追加写（AppendObject） | `append_object` | P1 | 真桶已验证 | `cos/append_ops_wbtest.mbt`、`cos/live_extra_test.mbt`（2026-10-22） |
| COS-OBJ-010 | 重命名（RenameObject） | — | P1 | 不纳入核心 | 官方 Python `rename_object` 仅支持 Rapid Bucket，普通桶改用 copy+delete |
| COS-OBJ-011 | 软链接（Put/GetSymlink） | `put_symlink` `get_symlink` | P1 | 部分真桶 | 建链真桶 403（账号权限），未验证；离线件已落 |
| COS-OBJ-013 | 对象内查询（SelectObjectContent） | — | P1 | 未开始 | 对象内查询 |
| COS-BKT-006 | 桶标签（Get/Put/DeleteBucketTagging） | `get_bucket_tagging` `put_bucket_tagging` `delete_bucket_tagging` | P1 | 已实现 | 读真桶受账号权限限制，未验证 |
| COS-BKT-007 | 桶日志（Get/PutBucketLogging） | `get_bucket_logging` `put_bucket_logging` | P1 | 已实现 | 读真桶受账号权限限制，未验证 |
| COS-BKT-008 | 防盗链（Referer） | `get_bucket_referer` `put_bucket_referer` `delete_bucket_referer` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写入未跑 |
| COS-BKT-013 | 网站托管（Get/Put/DeleteBucketWebsite） | `get_bucket_website` `put_bucket_website` `delete_bucket_website` | P1 | 已实现 | 读真桶受账号权限 403，未验证 |
| COS-BKT-009 | 生命周期（Get/Put/DeleteBucketLifecycle） | `get_bucket_lifecycle` `put_bucket_lifecycle` `delete_bucket_lifecycle` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-015 | 复制（Get/Put/DeleteBucketReplication） | `get_bucket_replication` `put_bucket_replication` `delete_bucket_replication` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-014 | 服务端加密（Get/Put/DeleteBucketEncryption） | `get_bucket_encryption` `put_bucket_encryption` `delete_bucket_encryption` | P1 | 已实现 | 读真桶受账号权限 403，未验证 |
| COS-BKT-010 | 清单（Inventory 四件） | `put_bucket_inventory` `get_bucket_inventory` `delete_bucket_inventory` `list_bucket_inventories` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-017 | 对象锁（Get/PutBucketObjectLock） | `get_bucket_object_lock` `put_bucket_object_lock` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-016 | 桶策略（Get/Put/DeleteBucketPolicy） | `get_bucket_policy` `put_bucket_policy` `delete_bucket_policy` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-011 | 自定义域（Get/Put/DeleteBucketDomain） | `get_bucket_domain` `put_bucket_domain` `delete_bucket_domain` | P1 | 部分真桶 | 读真桶受账号权限 403，未验证；写只落离线件 |
| COS-BKT-018 | 响应控制（Response Control） | — | P1 | 未开始 | 加速不在官方 Python 基线；响应控制未做 |
| COS-BKT-012 | 智能分层/配额/桶信息（IntelligentTiering/Quota/Info） | — | P1 | 未开始 | 智能分层、配额、桶信息 |

### P2 · 便利/安全层

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| COS-SEC-001 | STS/CAM 临时凭据（`x-cos-security-token`） | 未开始 | `Credentials` 现只有永久密钥 |
| COS-CNV-001 | 自动分片 / 断点续传 / 进度回调 | 未开始 | 高层 helper |
| COS-CNV-002 | TransferManager / 分页器 / 重试策略 | 未开始 | 与官方 SDK 高层入口对齐 |

### P3 · 可选模块

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| COS-EXT-001 | CI 数据加工（`ci_*`，官方 Python SDK 约 107 个方法） | 未开始 | 独立模块，不计入核心存储面 |
| COS-EXT-002 | 直播 / 媒体 / VOD | 未开始 | 独立产品线 |
| COS-EXT-003 | 批量任务 / 向量桶 / Rapid Bucket | 未开始 | 独立产品线或新存储形态 |

## 3. 不适用/边界

| 项 | 结论 | 理由 |
|---|---|---|
| Path-style 寻址 | 不适用 | 2024-01-01 后新建桶强制 virtual-hosted；真桶实测 path 403 |
| ListObjectsV2 | 不计入原生面 | 原生文档只列 V1；S3 兼容面实测过 V2，结论不互借 |
| PostObject | 不计入 P0 | 官方 Python SDK 未暴露 PostObject；浏览器表单协议，单列为扩展 |
| 桶创建/删除 | 纳入 P1，但不对 file-storage 门面开放 | 账号级动作 |

## 4. 下一批

1. 现有 16 法真桶已复核（2026-10-22）。
2. `delete_objects`、`upload_part_copy`、`list_multipart_uploads`、对象标签三件、条件请求、CRC64 读回已真桶绿；存储类回读已落，`post_object` 官方未暴露不追。
3. P0 绿后开 P1 控制面；CI 单独立项，不阻塞核心。
