# MCP 帖子图片读取

## 状态

2026-10-11 按用户授权加载独立插件 `blackroom-mcp-images`，重启 `app` 容器中的 Web 服务并启用 `discourse_read_post_image`。全站启用工具为 36 个。ChatGPT 的“BlackRoom 管理”工具目录为 36 个，“BlackRoom discobot 发布助手”为 17 个，两者均已刷新并显示新工具。源码位于 `plugins/blackroom-mcp-images/`；该目录受上游插件忽略规则影响，交付时必须单独归档，不能只依赖本仓 Git 状态。

## 接口契约

工具名称为 `discourse_read_post_image`，参数为：

```json
{"post_id": 123, "image_index": 1}
```

`post_id` 必填，`image_index` 从 1 开始，省略时为 1。图片按附件 ID 排序，并非正文显示顺序。每次返回一张图片，`structuredContent.images` 提供完整可读图片清单及序号，供继续调用。

返回内容含文本元数据及标准 MCP `ImageContent`：`type: image`、base64 `data`、`mimeType`。图片数据不重复塞进 `structuredContent`。支持 PNG、JPEG、GIF、WebP；仅支持已有的本站附件，不抓取用户提供的任意 URL，不包含未下载到本站的外链图或 SVG。

使用现有 `mcp:content:read` scope、帖子 Guardian 检查和附件 Guardian 检查。私信需要额外 `mcp:private-messages:read`；来自私信访问控制帖的附件也必须具有该 scope。只获取图片，不调用额外 AI 服务，不生成描述或修改帖子。

为 JSON 和元数据留出 16 KiB 预算后计算 base64 可容纳的图片大小。超大原图优先选用已有、大小合适的最大宽度缩略图，并返回 `resized: true`；不存在合适缩略图则返回工具错误，不生成新缩略图。缺文件、越界序号和无可读图片均返回明确错误。

协议依据：[MCP 工具图片内容规范](https://modelcontextprotocol.io/specification/2025-11-25/server/tools#image-content)。客户端实际是否把图片交给模型，需要单独实测。

## 验证

`check.rb` 使用实际 Rails、Guardian、MCP Server 与 JSON Schema，在事务内插入无回调的临时用户、帖子与附件引用，最后回滚；不签发 OAuth token、不发送通知，不修改已有上传文件，也不重启 Web 进程。调用示例：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner plugins/blackroom-mcp-images/check.rb'
```

此检查验证服务端行为，不能替代生产 HTTP 认证或 ChatGPT 真实看图验收。本地 RSpec 启动被未运行的 Redis 阻断，未把该次启动视为测试通过。

2026-10-11 最终检查通过 9 组断言：图片字节与 MIME、其他社团与非成员拒绝、管理员读取、scope 与序号校验、缺失文件与清单、多图选择、超大图拒绝、已有缩略图回退、私信 scope。临时数据与工具开关全部回滚；生产 Web 进程未变。3 个 Ruby 文件语法检查和定向 `bin/lint --fix` 通过。NAS 暂存源码与本地 SHA-256 一致，暂存路径为 `/home/muwei/discourse-docker-preview/staged/blackroom-mcp-images-20261011`。

## 加载、启用与回退

生产加载需按 [恢复与更新手册](resilience.md#每次更新的最小流程) 取得生产重启授权并保存 NAS 恢复材料。将插件部署到 NAS 持久源与运行容器的插件目录，确认未来重建的挂载或构建配置包含它，再重启应用 Web 进程。此插件无数据库迁移、无前端资源，无需为此升级 Discourse。

加载后通过 `McpPrimitiveUpdater` 或 MCP 管理后台仅启用 `discourse_read_post_image`，保留原群组、OAuth scope 与其他工具配置。刷新客户端工具目录后，用已授权连接读取一张已知图片，核验实际图像与模型判断。

首先回退工具开关：仅将该工具的 `McpPrimitive.enabled` 设为 `false`；不关闭整个 MCP 服务、不撤销已有连接。需要卸载时保留源码归档，移出插件加载目录并在获授权后重启 Web 进程。不要恢复数据库或覆盖其他插件。

## 线上交付记录

- NAS 持久源码：`/home/muwei/discourse-docker-preview/plugins/blackroom-mcp-images`。运行容器源码：`/var/www/discourse/plugins/blackroom-mcp-images`，校验与本地一致。
- launcher 配置只新增该插件的 volume；其余 YAML 内容经解析比较保持一致。当前容器未重建，因此此插件当前仍使用容器内文件，声明的挂载用于后续重建。
- 只重启 `/etc/service/unicorn`，新监督进程 PID 为 `421188`；启动初期源站返回 503，随后恢复 200。未重启数据库、Redis 或 Sidekiq。
- 使用 `McpPrimitiveUpdater` 在原启用清单上追加新工具，断言其余开关及全部群组 scope 不变。管理员和 discobot 的既有 OAuth 授权范围保留。
- 真实 HTTP `tools/list` 包含新工具；`tools/call` 读取帖子 ID `206` 返回 `image/jpeg`、262,489 字节，与原附件字节及 SHA-1 一致。解码图像与实际网页的走路姿态参考图一致。验收借用既有管理员授权生成了仅 profile/content read 的短期测试 token，原 token 未读取，测试 token 在 ensure 中撤销；这不是 ChatGPT 模型的实际调用。
- 已登录 Chrome 验证线上启用开关、两个 ChatGPT 连接的新工具清单，以及实际帖子图片。管理员连接首次刷新出现“无法更新应用”，在独立页面刷新后目录已包含新工具。没有断开连接、重新授权或扩大权限。
- 本聊天原有工具 schema 尚未动态增加新工具；未把客户端工具目录更新称为 ChatGPT 模型看图结论验收。
- 按发布契约创建公告话题 `147` 和教程话题 `146`，并完成首次浏览器正文、互链、作者和标签核验。随后在北京时间 20:54:16、20:54:26 被管理员账号 ID `1` 软删除；本次保留该删除状态，不恢复、不换编号重发。接口本身和客户端工具目录未受影响。发布清单、源码和首次浏览器证据仍保留，不能将这两个话题报告为当前可用。
- 本机证据：`outputs/mcp-images-20261011/`；发布清单：`outputs/blackroom-updates/mcp-images-20261011/`。

更新前完整恢复集合位于 NAS `/vol4/1000/backup/blackroom/mcp-images-before-20261011-2040`，含本次新生成的原生完整备份、已校验的异卷副本、受保护部署材料和程序回退镜像。镜像标签 `local_discourse/app:mcp-images-before-20261011`，ID `sha256:a84f74effef09f6eaaf656570bb9dea6a21c68a91ed681895077c83a624fee96`。本次核验归档可读、数据库/上传文件存在和校验一致，没有重新做恢复演练。

插件发布源单独保存在 `/vol4/1000/backup/blackroom/mcp-image-releases/`。变更前工具与群组 scope 快照为 `/shared/state/mcp-images-before-20261011.json`，只用于定向回退，不包含凭据。

上线后再次成功生成包含上传文件的完整备份 `blackroom-2026-10-11-125255-v2026-10-0-latest-20261006113418.tar.gz`，与 `/vol4/1000/backup/blackroom/daily/` 及 `mcp-image-releases/online-20261011/` 副本校验一致。后者另存新版受保护 `app.yml` 和插件源码归档。备份时点早于随后发生的公告删除，不代表删除后的最新数据库状态。
