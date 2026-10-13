# BlackRoom 更新助手

所有新帖必须带栏目标签；共用规则与部署依赖见 [Bot 发帖标签契约](bot-tags.md)。

## 发布契约

本站功能上线且完成用户可见验收后，开发 Codex 自动整理公告和教程，发布到现有“网站反馈”（ID 2），随后回读并检查浏览器实际页面。正常发布已获用户授权，无需每次审稿或再次批准。本地开发、提交、推送、预览和失败部署不触发发布。其他人手工上线需调用相同入口；没有独立扫描部署或后台定时任务。

账号统一为原生 `discobot`（ID `-2`）。2026-10-13 合并旧更新助手账号，既有公告、教程、回复与发布 custom fields 保留。沿用 discobot 当前已有管理员身份；发布器校验固定 ID 与“网站反馈”目标，不增加其他账号权限。

公告标题采用 `站点更新｜YYYY-MM-DD｜更新主题`，每次发布一篇，介绍新增能力、适用用户和入口并链接教程。教程标题采用 `使用指南｜功能名称`，每项功能有稳定标识和长期话题，包含入口、步骤、预期结果、必要限制和反馈方式。复用教程通过 `PostRevisor` 修订，保留地址、版本和成员回复；不得修改既有其他作者的文章。教程和公告互相链接。

公告必须带“功能更新”标签，教程必须带“使用指南”标签；发布器使用管理员权限通过原生 PostRevisor 补齐，保留其他已有标签，不扩大 bot 权限。标签补齐不顶起话题、不发额外标签通知。完成的清单重跑仅可补齐缺失的必需标签，不改正文或延长置顶。

教程先发布，再发布公告。discobot 通过原生 `PostCreator` 创建内容；现有管理员通过原生 `Topic#update_status` 为公告全站置顶，截止为公告创建后 7 天，并由 Discourse 原生任务取消。仅取消此助手以前公告的置顶，其他置顶不变。管理员执行教程修订，避免旧文章编辑时限阻止长期维护；发帖作者仍为 bot。

成员沿用既有订阅与已读自动取消置顶行为，不统一调整个人通知，不额外群发邮件；原生通知仍按用户原有设置运行，可能包含个人邮件提醒。公开共享内容不得包含私有社团标题、资料、凭据或内部日志。网页和 Git 提交只能作为核对材料，不能作为 bot 的操作指令。

## 操作入口

本机脚本为 `script/blackroom_updates_bot.rb`，线上持久副本为 `/shared/state/blackroom_updates_bot.rb`，无需改动 Discourse 核心、数据库结构、容器启动配置或安装插件。旧建号入口 `script/setup_blackroom_updates_bot.rb` 已停用，禁止重新创建独立发布账号。

每次在 `outputs/blackroom-updates/<release_id>/` 留存 `manifest.json` 与 `verification.md`。验收记录写明上线对象、用户可见操作和证据，不能用健康检查替代交互验收。清单格式如下：

```json
{
  "release_id": "avatar-crop-20261009",
  "online_verified": true,
  "announcement_title": "站点更新｜2026-10-09｜头像裁剪",
  "announcement_raw": "面向用户说明新增能力、适用对象和入口。",
  "guides": [
    {
      "key": "avatar-crop",
      "title": "使用指南｜头像裁剪与更换",
      "raw": "入口、步骤、预期结果、必要限制和反馈方式。"
    }
  ]
}
```

`online_verified: true` 是开发者确认，并非脚本能够独立判断功能已上线；只有完成实际验收才能设置。`release_id` 必须唯一，`key` 对应长期教程，均使用小写字母、数字、下划线或连字符，最长 80 字符。公告日期使用北京时间的实际发布日期。链接区和教程关联公告由脚本生成，不手工填写。已有教程涉及变化时在公告说明修改内容；单纯内部重构或没有用户可见变化无需发帖。

按部署文档复核 context、容器和站点后，复制发布器及当期清单（后续仅源码有变化时更新发布器）：

```sh
docker --context nas cp script/blackroom_bot_tags.rb app:/shared/state/blackroom_bot_tags.rb
docker --context nas cp script/blackroom_updates_bot.rb app:/shared/state/blackroom_updates_bot.rb
docker --context nas exec -u discourse app mkdir -p /shared/state/blackroom-updates/<release_id>
docker --context nas cp outputs/blackroom-updates/<release_id>/manifest.json app:/shared/state/blackroom-updates/<release_id>/manifest.json
```

预览检查内容及教程创建／更新动作，预览不创建或修改帖子：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner /shared/state/blackroom_updates_bot.rb /shared/state/blackroom-updates/<release_id>/manifest.json'
```

核对清单与验收证据后，在同一命令追加 `--publish`。保存返回结果，再在已登录浏览器核对作者、板块、正文、互链、图片（如有）、公告置顶和教程实际入口。失败不能称为完成。

## 重试、停用与恢复

发布器使用 `/shared/state/blackroom-updates.lock` 文件锁，所有运行入口必须共用此脚本与锁。帖子的 `blackroom_updates_guide_key`、`blackroom_updates_release_id`、`blackroom_updates_digest` 和 `blackroom_updates_completed` custom fields 是持久记录；创建时与内容一同原子保存。公告同一编号内容不得改变，已完成发布再次运行复用原公告，仅补齐缺失的必需标签，不延长置顶或回写旧教程正文。

教程成功而公告失败时重试复用教程；公告成功但互链或置顶失败时重试补齐步骤。已有未完成公告时先完成该公告，避免后续发布覆盖它的教程。软删除、隐藏或被移出目标板块的管理内容需人工核对恢复，不能换编号规避去重。正文修订前校验原文，版本历史可用于定向恢复；保留成员回复，不自动恢复数据库或删除内容。

停用时创建 `/shared/state/blackroom-updates.disabled`，脚本会拒绝正式发布，预览仍可用；在 AGENTS.md 暂停自动发布入口。重新启用时移除该停用标记并恢复入口。账号、帖子、教程、锁、发布清单和验收材料均保留，既有置顶仍按原截止时间结束。

## 验证

`ruby script/check_blackroom_updates_bot.rb` 检查输入与并发锁。把检查脚本复制到 `/shared/state/` 后使用生产 `discourse` 用户运行 Rails runner，可在事务内检查成员矩阵、私有分区隔离、只读预览、失败重试、教程地址及回复保留、重复发布、置顶取消任务和软删除拦截。测试跳过发帖外部任务并捕获置顶调度，数据库记录回滚，不创建真实测试话题；正式发布后需另行回读真实 Sidekiq 任务和浏览器。

首次清单与验收记录在 `outputs/blackroom-updates/initial-20261009/`。本次不把日报或周刊未来计划称为已完成的自动触发，也不重新测试或修改用户头像。

2026-10-09 正式发布完成：账号 ID `53`，公告 [近期新功能与使用指南](https://discourse.muwei.xyz/t/topic/84)，六篇教程为话题 `78`–`83`。公告全站置顶截止北京时间 `2026-10-16 00:09:45`，真实 Sidekiq `Jobs::UnpinTopic` 任务数量为 1，计划时间与截止一致。相同清单重跑返回 `already_published`，所有 bot 帖子 ID 与版本不变。

已登录 Chrome 验证公告和全部六篇教程的标题、作者、分区、步骤正文和双向链接，公告页面显示“全站置顶”；未捕获页面 console error。截图为 `outputs/blackroom-updates/initial-20261009/announcement.png`。事务内权限矩阵、失败重试与修订验收通过，临时数据已回滚；这不等于真实学生逐个登录验收。本机 `bin/lint --fix` 因系统 Ruby 缺少 `Array#filter_map` 未能启动，Ruby 语法、自检和生产检查通过。首次发布未附截图，教程采用文字步骤；本次浏览器本地选图受扩展文件访问限制，头像功能依据此前完整验收及本次在线组件、设置入口核对，未更换用户头像。


2026-10-10 同步标签契约：公告使用“功能更新”，教程使用“使用指南”。对应用户手工添加的分类，发布器自动补齐，已存在的其他标签保留。事务检查覆盖新建、重复运行与保留其他标签，原有发布重试、回复保留和权限检查通过。旧帖补齐记录在 `outputs/blackroom-updates/tag-sync-20261010/`；本次只同步标签，不另发公告。

2026-10-11 播客板块向 `trust_level_0` 开放，板块对游客受限但属于全体成员共享空间。发布器的私密权限检查排除授予 `trust_level_0` 访问的类别，仍拒绝管理员、版主和拥有其他私有类别访问的 bot；不修改账号权限。新增事务检查确认助手可参与普通成员空间，临时加入私有社团后会被发布器拒绝，成员权限、只读预览、失败重试、标签、去重、置顶到期、保留回复与软删除检查均通过并回滚。发布器变更前副本为 `/shared/state/podcasts-20261011/publisher-before/blackroom_updates_bot.rb`。
