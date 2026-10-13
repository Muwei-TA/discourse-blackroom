# BlackRoom 整机故障恢复（R2）

此机制用于保留当前站点开发过的功能，并恢复到最近成功备份的业务状态。GitHub 源码、NAS 本地备份、云端加密备份和隔离恢复演练是四种不同证据；任何一种不能代替另外三种。

## 存储与安全契约

- 生产部署：NAS `/home/muwei/discourse-docker-preview`，Docker `app`。
- 本地恢复包：`/vol4/1000/backup/blackroom/offsite/capture-<UTC时间>`；未完成包以 `.partial` 结尾，不能上传。
- 云端：账户 `841556b7f158ae0bc937a144cefbcb3b` 的私有 R2 桶 `blackroom-disaster-recovery`，`restic/` 前缀。公网访问关闭。
- NAS 受保护配置：`/vol4/1000/backup/blackroom/offsite/private/`，目录 `0700`、文件 `0600`。
- 上传前由 restic 加密。恢复口令必须保存在 NAS 之外；只有 NAS 上的副本不满足整机灾备。
- S3 凭据只授权该桶 Object Read & Write。Access Key ID 为 32 位十六进制字符，Secret Access Key 为 64 位十六进制字符；API Token 值不能填入 Secret Access Key。
- 恢复包包含配置与凭据，不能上传到 GitHub，也不能在 Mac 留存业务备份。

## 恢复包内容

| 制品 | 用途 |
| --- | --- |
| `forum-backup.tar.gz` | Discourse 原生数据库和上传文件备份，含主题、设置、群组、权限、帖子及用户 |
| `images.tar`, `forum-image.id` | 当前论坛程序快照和外部服务的兼容程序镜像，目标架构 linux/amd64 |
| `deployment-and-services.tar`, `forum-state.tar` | launcher、插件、脚本、私有配置、功能状态及外部服务部署源码 |
| `tabletop.dump`, `tabletop-roles.private.sql` | 桌游 PostgreSQL 在线逻辑备份与角色 |
| `drawpile-config.db`, `drawpile-files.tar` | Drawpile SQLite 在线一致性备份及持久文件 |
| `forum-model-config.tar.zst`, `models-download.json` | 模型别名、提示词、参数、摘要及 CPU 运行库；不含模型权重，恢复时按固定来源重新下载 |
| `tabletop-redis.rdb` | Redis 取证副本；恢复时不自动重放旧会话、授权票据或任务 |
| `containers.private.json`, `images.private.json`, `crontab.private.txt` | 私有部署核对材料；不能直接整体回放 |
| `manifest.json` | 每个制品的大小、SHA-256、版本及各服务备份时间 |

论坛原生备份与其他服务的采集时间不同，不提供跨服务事务一致性。进行中的内存游戏房间和未持久化画布不能恢复。外部 Pangolin、域名、Cloudflare、邮件供应商和第三方 OAuth 账户不由此桶重建，需要独立保留管理权限。恢复时不得重新启用已经取消的 ACG、梗图等发布任务。

## 配置、采集与上传

源码在 `script/disaster-recovery/`；NAS 执行副本位于 `/home/muwei/discourse-docker-preview/resilience/offsite/`。

```sh
ssh -t nas python3 /home/muwei/discourse-docker-preview/resilience/offsite/configure_r2.py
```

修正 S3 密钥时只替换密钥，保留仓库口令：

```sh
ssh -t nas python3 /home/muwei/discourse-docker-preview/resilience/offsite/configure_r2.py --replace-s3-keys
```

`backup.py` 校验权限、独立口令保存确认和仓库地址；首次访问成功且仓库确实不存在时初始化。访问被拒绝不会自动初始化或覆盖任何仓库。采集和本地缩减必须在原 NAS 执行；上传仅允许 `zstd-models-redownload` 格式，拒绝上传含 `forum-models.tar` 的原始包。采集校验 `/vol4` 挂载、剩余空间、论坛备份新鲜度、备份归档、模型内容和制品校验和。

```sh
ssh nas python3 /home/muwei/discourse-docker-preview/resilience/offsite/backup.py
```

上传已完成恢复包时把其完整 NAS 路径作为参数。成功记录在 `offsite/status.json`；失败记录在 `offsite/last-failure.json`，失败不覆盖此前成功记录，判断健康时必须比较时间戳。日志只保存在受保护目录，不向聊天输出完整日志。

程序目前不执行 `forget`、`prune` 或自动删除本地恢复包。容量会随备份增长；只有完成云端下载与恢复验证后，才应落实保留策略。首次云端验证未通过前，不把它称为可用的异地灾备，也不登记成功的定时机制。

## 在新机器下载

准备具有足够空间的 Linux amd64 主机、Docker、Python 3、zstd 和 restic；恢复工具本身不启动任何容器。使用源码仓库中的 `configure_r2.py` 与 `restore.py`，在终端隐藏输入桶密钥和 NAS 之外保存的恢复口令。

```sh
python3 script/disaster-recovery/restore.py /srv/blackroom-recovery --snapshot SNAPSHOT_ID
```

目标必须不存在。工具先执行 `restic check` 检查仓库结构，再执行 `restore --verify` 完整读回所选快照并校验，最后核验恢复包清单。不额外下载第二遍，也不宣称验证其他历史快照的全部数据。成功输出包含 `snapshot_full_read_passed` 和 `checksums_passed`；`services_restored` 始终为 false，不能把下载成功当成站点恢复成功。

在 NAS 做云端下载演练时，可以使用已经受保护的配置：

```sh
ssh nas python3 /home/muwei/discourse-docker-preview/resilience/offsite/restore.py /vol4/1000/backup/blackroom/offsite/rehearsal-UNIQUE_ID --snapshot SNAPSHOT_ID --use-nas-config
```

## 站点恢复与切流顺序

1. `restore.py` 会自动解压 `zstd-models-redownload` 制品，并核对清单中的 `uncompressed_size` 与 `uncompressed_sha256`。手工恢复时需用 `zstd -d --keep` 解压并做同样校验。核对镜像标签，加载 `images.tar`，核对 `forum-image.id`；先恢复同版本，再考虑升级。
2. 建立独立的新卷和 internal 网络。不要复用生产 `/shared`，不要启动 Newt，不对外暴露演练服务。
3. 在新卷恢复 `forum-state.tar`。关闭 cron、anacron、邮件和自动任务，覆写生产域名、SMTP 等启动配置。
4. 初始化同版本 PostgreSQL 和扩展，运行 `rake db:migrate db:seed`；使用 Discourse 原生 `discourse enable_restore` 和 `discourse restore BACKUP --disable-emails` 导入下载的 `forum-backup.tar.gz`。不能以直接导入 SQL 替代原生恢复。
5. 在独立服务恢复桌游 PostgreSQL、Drawpile SQLite、模型与程序。核对模型摘要与 CPU 推理；不重放旧 Redis 授权票据。
6. 验证主题、图片、播客、编辑器、自定义插件、社团访问权限、MCP 配置、AI 功能及游戏入口。真实邮件、OAuth 和公网切流需要另外验收。
7. 恢复完成、回退方案明确后，才在目标主机配置受保护凭据和公网连接。DNS/隧道切流及生产数据覆盖必须获得具体授权。

## 当前验收状态（2026-10-13）

- 私有 R2 桶已创建，NAS 受保护配置已保存，口令已由用户确认独立保存。
- `capture-20261013T123107Z` 已生成，制品总大小 15,327,790,976 字节；论坛原生备份校验包含 138 个非空上传文件。
- 用户核准 2.77 GB 缩减包后上传完成；2026-10-13 21:17:22（北京时间）生成快照 `387d608da814f99712cbf6c2d72f58729d6e05c7c290e3f83b331d77a6d1a13c`，仓库结构检查通过。R2 列表核对为 161 个对象、2,766,400,090 字节，含仓库元数据。
- 18 项离线边界、无损压缩往返、模型权重排除、自定义配置保留及下载校验测试通过。
- 原始包 15.33 GB，已生成不含模型权重的压缩包 `capture-20261013T123107Z-lean`，含清单精确大小 2,767,034,167 字节（约 2.77 GB），减少约 81.9%。模型权重 6,973,825,664 字节已排除，自定义配置保留。所有压缩档逐个解压后摘要一致。
- 此快照的论坛数据时间点为 2026-10-13 20:26:30，程序与配置采集始于 20:31:07（北京时间）；之后的修改不由该快照覆盖。
- 首次上传预算 3 GB，实际云端存储约 2.77 GB。用户随后要求“不用下载”，因此未执行云端下载、模型下载或恢复演练，没有这部分大流量下行。后续定时频率和保留策略另行确认。
- 已验证：本地恢复档、无损压缩、上传完成、云端快照存在及仓库结构。未验证：云端制品完整读回、当前版本隔离恢复。定时异地备份未启用；这是一份手动异地恢复副本，不是已验收的自动灾备机制。2026-10-09 的旧恢复演练不能代替这些检查。

## 无损缩减与流量复核

`compact.py` 在 NAS 本地压缩 images、deployment、forum-state，并从 models 中排除三份模型权重，仅保留模型自定义配置和 CPU 运行库。原始恢复包完整保留。每个压缩制品均解压流式核验原 SHA-256，并在新清单记录压缩前后的大小和摘要；不执行上传。缩减结果需经用户确认后才上传。用户核准缩减包后已上传；随后取消下载，尚未执行读回。未来如执行，读回只完整恢复所选快照一次，减少重复下载。


模型恢复需另外下载约 6.97 GB（审核 4.68 GB、标签 1.16 GB、翻译 1.13 GB），这些流量来自模型上游而不是 R2。2026-10-13 对三个固定下载地址执行 HEAD 均返回 200；Ollama 上游 manifest 和 Hugging Face 固定提交的 LFS SHA-256 与当前权重匹配。未为验证重新下载这 6.97 GB。未来上游可用性不是本备份保证范围。

解压模型配置后，按文件清单恢复 manifests、小型 blobs 和 CPU 运行库，再执行以下命令把省略的权重放入恢复模型目录的 blobs 子目录；工具按固定 SHA-256 和大小校验，不启动 Ollama、不覆盖已有文件：

```sh
python3 script/disaster-recovery/download_models.py RECOVERY_SET/models-download.json /srv/blackroom-models/blobs
```
