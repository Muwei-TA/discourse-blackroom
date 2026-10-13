# discobot 的 ChatGPT MCP 发布连接

## 目标与现场状态 — 2026-10-11

用户要求让 ChatGPT 以原生 `discobot` 身份发布话题与回复。discobot 的用户 ID 为 `-2`，当前 active、approved，保留内置管理员身份及 TL4；论坛引导插件保持启用。本次没有新增权限群组或修改管理员群组的 12 个 MCP scope。

discobot 已因其管理员群组成员资格拥有原生 MCP 资格，但原有 ChatGPT 授权绑定的是用户 ID 1。原生 `discourse_create_topic` 与 `discourse_create_post` 始终使用 OAuth 授权用户作为作者，`author_username` 仅用于校验同一作者，不能让管理员改用 discobot 身份。OAuth 授权页面拒绝管理员模拟登录状态；应使用 discobot 本人的正常登录完成授权。

## 登录设置与当前进度

discobot 原来使用内置占位邮箱，尚未确认邮箱，密码由初始化程序随机生成。仅设置密码不能完成普通登录。

用户指定 `discobot@blackroom.qzz.io` 为其控制的独立收件邮箱，并授权用于登录设置。通过原生 `UserEmail` 校验与 `EmailUpdater#update_user_email` 配置，保留后台操作日志；生成并发送了一次原生密码重置邮件，没有读取或输出邮件链接、验证码或密码。

服务商记录显示邮件 `delivered`；用户随后确认真实收件并亲自通过官方页面设置密码。现场回读邮箱确认状态为 true、密码更新时间已改变，已登录 Chrome 首页显示“欢迎，discobot”。已有 ChatGPT 管理员 OAuth 授权仍保持 active。

变更前记录保存在 NAS 容器内 `/shared/state/discobot-login-before-20261011-085810.json`，不含密码、密钥或 token。用户亲自完成 OAuth 授权后，站点回读授权 ID 2，用户 ID `-2`，客户端 ID 1，状态 active，scope 恰为下述 3 个，另有 1 个有效 token。管理员 ID 1 的既有授权仍保持 active。

## 独立的 ChatGPT 连接

已准备 `BlackRoom discobot 发布助手` 的自定义 MCP 表单，地址为 `https://discourse.muwei.xyz/mcp`，采用 ChatGPT 官方 CIMD 客户端，关闭 OIDC。仅申请以下 scope：

- `mcp:profile:read`
- `mcp:content:read`
- `mcp:content:write`

基础 scope 为 `mcp:profile:read`。确认 discobot 正常登录后创建插件，OAuth 确认页列出的实际申请及可授予范围均为上述 3 个，最终由用户亲自点击授权。证据为 `outputs/discobot-mcp-20261011/oauth-scopes-prepared.png`、`oauth-consent.png` 与 `chatgpt-connected.png`。

插件 ID 为 `plugin_asdk_app_6acb513bf21081918623bb56d7b4ebdf`，设置入口为 [discobot 发布助手设置](https://chatgpt.com/settings/plugins-settings/plugin_asdk_app_6acb513bf21081918623bb56d7b4ebdf)。已连接账户昵称为“discobot 发布身份”，客户端工具权限保留“允许低风险操作”。在 ChatGPT 选择“BlackRoom discobot 发布助手”后发出具体发布或回复请求。重新连接时仍须使用 discobot 正常登录并完成用户 OAuth，不要在数据库中人工制造用户授权，或用管理员模拟登录规避原生授权检查。

原生内容 scope 的粒度包含创建和编辑。本次全站已开放工具中的 16 个工具可供这个 scope 集合使用：分区列表、话题与帖子查询、搜索、标签、当前用户、用户公开信息、新话题、回复及编辑话题/帖子；不包含审核、成员管理、站点设置、主题或私信工具。discobot 本身具有管理员身份，因此内容读取可能覆盖其可见的私有分区，内容编辑仍受该账号原生 Guardian 权限约束。3 个 scope 不会把此网页账号降为普通成员。

未来正式发布需确定分区/话题和具体正文，新话题遵守栏目标签契约；建立 OAuth 并不授权自动生成或发布不明确的业务内容。

## 已完成的服务端检查

使用内部请求上下文确认 3 个 scope 下目录为 16 个工具，发布话题和回复工具存在，管理工具不存在。管理员账号传入 `author_username: discobot` 被原生检查拒绝。

在数据库事务内调用原生 `CreateTopic` 和 `ReplyTopic`，两条帖子的 `user_id` 均为 `-2`。临时话题和帖子全部回滚，进程内抑制外部任务与 MessageBus 通知；没有公开测试帖子或发送测试通知。该结果验证服务端作者行为，不代替真实 discobot 登录、OAuth 和 ChatGPT 调用。

真实 OAuth 完成后，生产审计确认 user_id `-2` 的 `discourse_current_user_get`、分区/话题列表、搜索、读取话题与两次 `discourse_update_post` 均为 success、HTTP 200。编辑动作由用户在另一个 ChatGPT 对话中发起；本任务只读取并核验记录，没有另行发布或编辑内容。新话题和回复的作者行为依据上述事务检查，未新增公开测试话题来重复验收。

## 撤销与恢复

discobot OAuth 建立后，可在 `/admin/config/mcp/authorizations` 单独撤销用户 ID `-2` 的授权，不要撤销用户 ID 1 的管理员连接。关闭专用 ChatGPT 插件也应仅针对该发布连接。

若停止为 discobot 提供网页登录，按具体授权通过原生密码、登录会话及邮箱管理定向处理；没有保留旧随机密码副本，不能声称可恢复为原密码。邮箱设置前记录只用于核对结构状态，不能恢复已失效的邮件确认链接或登录会话。
