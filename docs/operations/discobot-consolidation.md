# 统一机器人身份

2026-10-13 起，BlackRoom 所有机器人发布、回复、栏目、站点更新和使用指南，以及 AI 垃圾信息初筛，统一使用原生 `discobot`（ID `-2`）。原生系统账号 `system`（ID `-1`）继续承担系统事件。

## 已实施

- 原生 `UserMerger` 合并并移除 `acg_daily_bot`（44）、`meme_bot`（48）、`blackroom_update_bot`（53）和 `discourse_ai_spam`（-3）。25 条机器人帖子及 2 条审核记录归属 discobot。未修改正文、话题地址、回复数量、删除状态、置顶时间、发布 custom fields 或分区权限。
- 三个发布器固定使用 discobot，并校验用户 ID `-2`。更新发布目标仍固定为网站反馈（2），日报与周刊沿用各自分区、标签及去重逻辑。历史内容转移后，原发布记录仍参与去重和教程维护。
- 原生 `ai_spam_detection_user_id` 设置为 `-2`；`SpamScanner.ensure_flagging_user!` 不会再创建独立审核账号。未更改模型、扫描范围和人工审核逻辑。命中只创建审核建议，管理员决定，不自动隐藏、删除或禁言。
- discobot 本次变更前已经是管理员、TL4；沿用已有身份，未扩大其 OAuth scopes。它原有教学与私信功能保留。原先普通发布 bot 的私有分区不可见检查不适用于此已有管理员；发布器仍只使用确定的栏目目标，公告不得包含私有社团信息。
- 本地与 `/shared/state/` 三个发布器、相关检查及三个 setup 入口已同步。旧 setup 入口现在直接报错，不重新创建账号。AGENTS.md 已保存统一身份契约。

## 备份及回退边界

变更前数据库归档和脚本集合仅保存在 NAS：`/vol4/1000/backup/blackroom/discobot-consolidation-20261013/discourse.dump` 与 `publishers-before.tar.gz`，权限 0600。`pg_restore -l` 已验证数据库归档目录可读。合并前的脱敏内容核对材料保存在容器 `/shared/state/discobot-consolidation-before.json`（0600）。

本次未做数据库恢复演练。账号合并不能通过简单恢复旧脚本撤销；恢复数据库会覆盖后续业务写入，必须另行取得具体授权并使用隔离演练。不得仅回退发布器而令其引用已不存在的账号，也不得清空审核身份设置以触发自动建号。

## 验收证据

本地记录在 `outputs/discobot-consolidation-20261013/`。定向 lint、自检、事务回滚检查分别验证公告与教程发布、失败重试、去重、标签、回复保留、置顶任务和审核行为。浏览器确认旧公告 136 的作者为 discobot；AI 审核后台启用、本地模型及智能体保持不变，举报筛选链接使用 `flagged_by=discobot`。

这是身份维护，不新增成员功能或操作步骤，不额外发布公告。事务检查不留下真实测试帖，未向成员发送额外通知；不把事务验收称为真实学生登录操作。日报未来定时触发是否存在与账号统一是不同事项，本次不新建或恢复定时任务。

全部相关事务检查已通过并回滚，日报/周刊自检及定向 lint 通过。三个发布器本地与生产 SHA-256 一致。ChatGPT `BlackRoom discobot 发布助手` 的真实身份读取返回 `id=-2`、`username=discobot`，scopes 仍为内容读写与身份读取；不需要重新 OAuth。浏览器未捕获 console error。
