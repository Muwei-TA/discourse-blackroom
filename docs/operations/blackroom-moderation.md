# BlackRoom 内容审核

2026-10-13 当前身份契约：发布与 AI 审核统一使用 `discobot`（ID `-2`）。旧账号已合并，原有内容和审核记录保留；下方带日期的旧账号记录仅为历史。审核仍由管理员最终决定，不自动隐藏、删除或禁言。详见 [统一身份记录](discobot-consolidation.md)。

2026-10-10 配置：原生关注词与 Discourse AI 垃圾检测；管理员作最终决定。JEV 保留独立服务，未接入发帖链路。其英文模型在前期中文测试中不足以承担本站垃圾信息初筛。

## 生效范围与处理

- 8 条关注词正则采用 `require_approval`，覆盖刷单/返利招揽、博彩开户、假证与个人资料交易、保证金诈骗、成人服务广告和直接暴力威胁。词组组合匹配，避免仅凭“赚钱”“保证金”等普通词拦截。命中的新帖在发布前等待人工批准；引用或反诈讨论仍可能命中组合规则，由管理员判断。
- `discourse_ai_enabled=true`、`ai_spam_detection_enabled=true`。原生范围为 TL0/TL1 用户的前 3 篇帖子，沿用插件的新帖及符合条件的编辑触发；不是全站历史帖扫描。私信、管理员/机器人和其他原生排除条件沿用上游逻辑。
- 本地 `Qwen2.5 7B` 判断作者意图，只有 `intent=promotion` 且 `spam=true` 才送审。正常活动、批评、文学引用、反诈提醒不应仅因涉及敏感词被 AI 判为垃圾。
- AI 命中创建 `ReviewableFlaggedPost`，保留帖子可见与作者正常使用权限，不自动隐藏、删除或禁言。管理员在 `/review` 查看理由并处理。敏感词发布前审批与 AI 发布后建议是两种不同流程。
- 人工举报及其他原有站点防垃圾规则不受该插件修改；不能把本配置理解成全站所有自动处置都被关闭。

## 本地模型与连接

NAS Ollama 原有服务仍只监听 `127.0.0.1:11434`。专用别名 `blackroom-moderator` 来自 `qwen2.5:7b-instruct`，CPU 推理，8 线程、4096 上下文、256 输出 token、温度 0，不占用 OpenViking GPU 模型。模型进程实际内存约 5 GB；现有 Ollama 主服务没有因本次配置添加全局内存限制，不能把代理资源限制当成模型限制。

`blackroom-ollama-proxy` 仅监听 Docker 网关 `172.17.0.1:11435`，原有 POST `/v1/chat/completions` 用于审核；2026-10-11 为 [官方标签推荐](ai-tag-suggestions.md) 增加 POST `/v1/embeddings`，两条路由均必须使用 bearer 认证，其他路径拒绝。代理限制 1 CPU /128 MiB、只读根目录、丢弃 capabilities。Key 仅保存在 NAS 受保护文件及模型凭据中，不写到本机、文档或日志。OpenAI-compatible 是本地协议，内容未发送给 OpenAI。

原生 FinalDestination 阻止私有地址。插件仅对精确地址 `172.17.0.1` 与端口 `11435` 设置固定连接 IP，其他目标仍执行原生检查；`allowed_internal_hosts` 未扩大。该例外适用于此端口的 HTTP 连接，代理仍负责认证与精确路由校验。未来变更 Docker 网关或代理端口时必须同步更新并重验，不能改为任意内网地址绕过。

## 持久化与回退

自定义插件 `discourse-blackroom-moderation` 持久保存于 `/vol1/docker/discourse-preview/shared/plugins/discourse-blackroom-moderation/plugin.rb`，部署源码副本 `/home/muwei/discourse-docker-preview/plugins/discourse-blackroom-moderation/plugin.rb`。容器 `/var/www/discourse/plugins/discourse-blackroom-moderation` 链接到 `/shared/plugins/`；部署 `hooks.after_code` 保留该链接。应用进程重启后加载，不需要数据库迁移。

规则源与行为检查位于本机 `work/blackroom-moderation/`，容器副本 `/shared/state/blackroom-moderation/`。初始设置快照 `before-20261010.json`、新建规则 ID `rule-ids.json` 和部署 YAML 原副本 `app.before-blackroom-moderation-20261010.yml` 均留在 NAS；部署 YAML 含凭据，不显示全文。

优先回退顺序：用 `SiteSetting.set_and_log` 关闭 `ai_spam_detection_enabled`；保留已有人工审核项；必要时仅撤销本次 8 条关注词并恢复快照中的正则设置。先关闭 AI 再撤下插件，否则原生 AI 命中可能重新自动隐藏/禁言。停用代理不删除模型、数据或日志；无需全局容器重建或数据库恢复。

## 验收及限制

原生 `SpamScanner.test_post`：正常社团活动 false、刷单诈骗 true、反诈提醒 false；直接模型六个中文样本全部符合预期。原生处理路径事务测试确认命中创建待审项、帖子不隐藏、话题可见、作者不禁言、重复处理不重复建项、管理员可审核、普通成员不可审核、管理员忽略后重复扫描不重新打开审核项。测试用户、帖子、模型审计与审核项事务回滚，不发送测试通知。

原生 NewPostManager 事务检查确认敏感词命中新帖进入待审批队列，未公开发布。浏览器关注词测试已验证诈骗招揽命中、反诈提醒未命中。启用后的原生扫描检查结果保存 `work/blackroom-moderation/check-results.jsonl`。管理员重新登录后，浏览器确认 AI 垃圾信息页面开关开启，所选模型与智能体正确；审核入口正常，当前待处理为空。没有保留垃圾测试帖，具体审核项及处理动作以事务测试为证据。截图为 `work/blackroom-moderation/ai-admin.png`。

有限样本不能代表准确率。CPU 原生扫描通常几十秒，冷加载更慢；异步检测期间帖子可见。模型失败不直接处罚用户。仅在新的故障、配置变更或误判样本出现时追加检查，管理员应按本站实际内容继续校准规则。

2026-10-10 已发布并浏览器验收：[更新公告](https://discourse.muwei.xyz/t/topic/97)、[发帖审核与误判反馈指南](https://discourse.muwei.xyz/t/topic/96)，作者 BlackRoom 更新助手、网站反馈，正文与互链正确。公告全站置顶截止北京时间 2026-10-17 14:42:36。发布清单、结果和截图在 `outputs/blackroom-updates/moderation-20261010/`。
