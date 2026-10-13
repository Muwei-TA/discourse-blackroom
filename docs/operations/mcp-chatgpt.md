# BlackRoom MCP 与 ChatGPT 管理接入

## 已完成的站点配置 — 2026-10-11

用户指定目标客户端为 ChatGPT，操作范围为管理成员、审核与站点配置，并包含内容读写。使用原生 MCP 配置，没有修改 Discourse 核心代码或重启容器。

- MCP 地址：`https://discourse.muwei.xyz/mcp`。
- 后台：`https://discourse.muwei.xyz/admin/config/mcp`。
- 启用 35 个工具、12 个 OAuth scope，群组访问规则仅授予 `admins`（ID 1）。
- CIMD 策略为 `approved_domains`，允许域名仅 `chatgpt.com`。
- 已通过原生 `DiscourseMcp::OAuth::ClientResolver` 获取、验证并注册官方客户端。客户端记录 ID 1，状态 `approved`，`client_id` 为 `https://chatgpt.com/oauth/client.json`，回调为 `https://chatgpt.com/connector_platform_oauth_redirect`。
- 用户在 Chrome 完成真实 OAuth 后，站点已回读 1 条活跃授权和 1 个有效 token，ChatGPT 插件设置显示账户“已连接”。插件 ID 为 `plugin_asdk_app_6acb4986d6088191b907219eb94ad61c`。凭据未被读取或输出。

本站的 OAuth 发现声明支持 CIMD、PKCE S256 与 `none` token endpoint authentication。ChatGPT 官方 CIMD 文档同时支持 `none` 和 `private_key_jwt`，两端有兼容的公共客户端模式，无需客户端密钥。参考 [OpenAI OAuth 文档](https://developers.openai.com/plugins/build/auth)。

## 开放能力与边界

| 范围 | 工具能力 |
| --- | --- |
| 身份 | 获取当前授权用户 |
| 内容 | 搜索帖子、列出话题与标签、读取话题/帖子/回复，创建与编辑话题和帖子 |
| 分区 | 列表、详情、创建与更新 |
| 成员 | 用户列表与详情、创建用户、管理激活状态、读取审核概况 |
| 群组 | 群组详情、成员列表与成员申请列表 |
| 审核 | 审核队列、详情、数量、帖子修订，以及原生可用的审核动作 |
| 设置 | 查询与更新普通站点设置；原生工具屏蔽凭据类设置 |

原生群组 MCP 工具只提供读取能力；本次配置不提供添加/移除群组成员的操作。没有开放私信、聊天、主题、草稿、Data Explorer 或专门的删除工具。审核动作仍可能改变内容或成员状态；授权能力不代表已批准未来每次业务操作。

12 个 scope 为：`mcp:profile:read`、`mcp:content:read`、`mcp:content:write`、`mcp:categories:read`、`mcp:categories:write`、`mcp:groups:read`、`mcp:users:read`、`mcp:users:write`、`mcp:moderation:read`、`mcp:moderation:write`、`mcp:site-settings:read`、`mcp:site-settings:write`。

管理员自身可读取私有分区，因此管理员同意授权后，ChatGPT 在这些工具范围内也可能读取其可见的私有帖子。普通成员未获 MCP 访问权限；这不会把私有分区变成公开分区。

## ChatGPT 侧配置

已在已登录 Chrome 的 ChatGPT“插件 → 添加 → 添加自定义 MCP 服务器”中准备名称 `BlackRoom 管理`、上述服务器 URL 与 OAuth。高级设置自动发现的 CIMD 客户端与回调 URL 均正确。

默认申请 scope 已收敛到上述 12 个，基础 scope 为 `mcp:profile:read`；关闭 OIDC，使用本站原生 OAuth。ChatGPT 插件权限保留“允许低风险操作”，高风险写入仍由客户端请求许可。

首次自动提交创建时页面返回“当前环境不允许创建自定义应用。请检查工作空间权限或安全设置”。用户手动继续后已创建并完成真实 OAuth，后续以插件设置和站点授权记录为准。没有改变 ChatGPT 工作空间权限或安全设置，也没有在数据库中人工创建用户授权。首次失败截图作为过程证据保留。创建步骤参考 [OpenAI 自定义 MCP 文档](https://developers.openai.com/api/docs/guides/custom-mcp-server)。

使用入口为 [BlackRoom 管理插件](https://chatgpt.com/plugins/plugin_asdk_app_6acb4986d6088191b907219eb94ad61c)，点击“在聊天中试用”，或在聊天中选择此插件。连接管理见 [插件设置](https://chatgpt.com/settings/plugins-settings/plugin_asdk_app_6acb4986d6088191b907219eb94ad61c)。

用户另要求以 discobot 发布和回复。该需求使用独立身份连接，保留此管理员连接；登录准备、内容 scope、作者校验和验收边界见 [discobot 发布连接](discobot-mcp.md)。

## 验证和恢复

服务端内部检查通过：管理员 MCP 访问为允许，`tools/list` 返回 35 个所选工具，两个社团的普通成员和非成员 MCP 访问均拒绝；私有分区可见性依次为 `[true,false]`、`[false,true]`、`[false,false]`，管理员保留两分区访问。临时账号和群组成员数据在事务结束后全部回滚。此检查使用内部请求上下文，没有签发测试授权或 token，不代替真实 ChatGPT OAuth 与工具调用。

随后通过 ChatGPT 独立聊天发起只读验收，生产 MCP 审计记录确认 `discourse_current_user_get` 与 `discourse_get_review_queue_count` 均成功、HTTP 200，授权 scope 与所需 12 个一致，无 MCP 审计错误。ChatGPT 页面显示“无法加载此回复”，刷新后仍未恢复，因此真实服务端调用通过，但该次聊天的最终回复展示未验收通过；未进行业务写入测试。

配置前快照在 NAS 容器内 `/shared/state/mcp-chatgpt-before-20261011-082734.json`，包含原 CIMD 策略、工具开关、群组 scope 和客户端记录标识，不含凭据。创建阻塞截图为 `outputs/mcp-chatgpt-20261011/chatgpt-create-blocked.png`。

应急关闭可将原生 `mcp_server_enabled` 设为 `false`；单独禁用 ChatGPT 可在 OAuth 客户端页面阻止客户端 ID 1，并检查原生授权撤销状态。精确恢复本次配置时，根据快照通过 `McpPrimitiveUpdater`、`McpAccessRuleUpdater` 与原生 SiteSetting 恢复对应范围；不要恢复整库或覆盖后续用户变更。

本次为管理员运维接入，未向普通成员开放功能或新增成员操作步骤，不触发更新助手的成员功能公告与教程发布。
