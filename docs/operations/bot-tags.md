# Bot 发帖标签契约

所有栏目内容发布 bot 在新建话题时必须带标签。2026-10-13 起所有栏目发布、更新公告、教程和 AI 审核统一使用原生 `discobot`（ID `-2`）；保留原生系统账号 `system`。旧的三个栏目账号与独立 AI 审核账号合并到 discobot，不再创建其他 bot。

| 发布账号 | 内容 | 必需标签 |
| --- | --- | --- |
| `discobot` | ACG 日报 | `acg日报` |
| `discobot` | 梗图周刊及试刊 | `哪来的傻缺图` |
| `discobot` | 更新公告 | `功能更新` |
| `discobot` | 使用教程 | `使用指南` |

`script/blackroom_bot_tags.rb` 复用既有更新助手的 `PostRevisor` 标签补齐方式：管理员执行标签修订，保留已有标签，`bypass_bump: true, silent: true` 避免顶帖和额外标签通知；作者为 discobot。新建帖子与必需标签在同一独立事务中保存，标签失败即回滚，不能返回 `published`。普通发布通知沿用站点及个人设置。

同日/同清单 `--publish` 重跑会补齐缺失标签，不重复发帖、不改正文、不延长置顶；预览不写入标签。被移除的梗图话题禁止借重跑继续修订。标签属于话题，回复沿用所属话题标签。原生 `system` 的系统事件与 discobot 的初始化说明、私信教学不属于栏目发布流程，原有教学行为保留；AI 审核身份已同步切换为 discobot。

新增栏目必须复用 discobot，并接入同一标签补齐逻辑，明确栏目标签。不要只在自动任务提示词里要求加标签，也不要为方便 bot 打标签降低全站标签权限。

## 部署及验证

三个发布器通过 `require_relative` 依赖 `blackroom_bot_tags.rb`，部署和恢复时必须将这四个文件放在同一目录。线上持久路径均为 `/shared/state/`；NAS cron 和梗图自动任务继续使用原入口。无需重启容器。

```sh
docker --context nas cp script/blackroom_bot_tags.rb app:/shared/state/blackroom_bot_tags.rb
```

发布器按各自手册复制。变更前副本在 `/shared/state/bot-tags-before-20261010/`；回退时恢复三个发布器即可，保留 helper 与现有帖子标签。旧标签修订记录使用原生 `PostRevision`；不通过数据库整体恢复撤销标签。

`script/check_blackroom_bot_tags.rb` 使用生产 Rails 的事务回滚检查日报/周刊新建、标签失败回滚、重跑补齐、预览只读、其他标签保留、正文/顶帖时间不变及删除拦截。RSS 使用合成数据，上传边界复用已有上传，不抓取新闻、不上传测试文件，不留下测试话题。更新助手继续使用 `script/check_blackroom_updates_bot.rb` 验证公告/教程及发布重试。定向 lint、自检、真实旧帖标签回读和浏览器页面分别留证在 `outputs/bot-tags-20261010/`。

本次为已有栏目标签维护，不新增成员功能或操作步骤，不另发更新公告。
