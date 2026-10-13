# ACG 日报机器人

2026-10-13 当前身份契约：发布与 AI 审核统一使用 `discobot`（ID `-2`）。旧账号已合并，原有内容和审核记录保留；下方带日期的旧账号记录仅为历史。审核仍由管理员最终决定，不自动隐藏、删除或禁言。详见 [统一身份记录](discobot-consolidation.md)。

2026-10-12 按用户要求删除每日调度：已从 NAS 用户 `muwei` 的 crontab 移除 `blackroom-acg-daily` 注释和 `/acg-daily/run.sh` 调度行，包括 12:00 首次执行及三次重试。回读确认其他任务完整保留，检查时没有正在运行的 ACG 发布进程。栏目、账号、已有帖子、脚本和翻译缓存保留；下述调度规则为历史配置，手动入口仍可执行。变更前快照位于 NAS `/home/muwei/discourse-docker-preview/acg-daily/crontab-before-removal-20261012T024703Z.txt`；恢复时只添加该任务的两行，不整体覆盖现有 crontab。

所有新帖必须带栏目标签；共用规则与部署依赖见 [Bot 发帖标签契约](bot-tags.md)。

2026-10-08 配置于 `https://discourse.muwei.xyz`。用户确定内容为动漫、游戏、ACG 热点，以及新番资讯、预告、开播消息；新建公共分区，每天北京时间 12:00 发帖。

## 线上对象

- 分区：`ACG 日报`，ID `48`，`/c/acg-daily/48`。使用 `everyone: full`，与普通公共分区相同；不改变公网入口认证要求。
- 发帖账号：`acg_daily_bot`，ID `44`，显示名 `ACG 日报机器人`。普通 TL1，非管理员、非版主，不加入私有社团。
- 首篇日报：`/t/topic/70`，2026-10-08 手动触发发布，两个栏目各 6 条。成员可回复讨论。
- 订阅：成员在分区通知菜单选择“关注第一个帖子”可收到新日报通知。未强制订阅全站成员；邮件遵循个人通知设置。

## 内容与边界

订阅源在 2026-10-08 扩充为 5 个，新增来源均从实际 NAS 容器验证 RSS 可读、发布时间可解析及条目链接域名：

| 栏目 | 来源 | RSS |
| --- | --- | --- |
| 游戏与 ACG 资讯 | 机核 | `https://www.gcores.com/rss` |
| 游戏与 ACG 资讯 | Nintendo Life | `https://www.nintendolife.com/feeds/latest` |
| 游戏与 ACG 资讯 | Eurogamer | `https://www.eurogamer.net/feed` |
| 新番资讯、预告与开播 | Anime News Network | `https://www.animenewsnetwork.com/news/rss.xml?ann-edition=us` |
| 新番资讯、预告与开播 | Crunchyroll News | `https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss` |

Anime News Network 的无参数地址在 NAS 返回 301，使用已核验的最终地址。Crunchyroll 的 RSS 服务域名与条目链接域名不同，文章只允许 `crunchyroll.com`，不把任意外链加入日报。

每个栏目合并其全部来源，按发布时间取最新的最多 6 条，每条标明实际来源。仍为每天一篇、最多 12 条，而不是每个来源各发 6 条。附原站链接，不转载全文、不提供下载资源。游戏栏目使用中英文标题关键词筛选资讯，新番栏目筛选 anime、trailer、premiere、debut、teaser、broadcast。过滤明显成人关键词，包含英文 nudity、X-rated、full-frontal；这不是完整的编辑审核。海外标题提供中文译文并保留原文，涵盖当季及未来已公布作品，不宣称为全网热度榜或严格限定当季的追番更新表。

抓取窗口从上次成功发帖时间开始，最长回补 72 小时；首发回看 24 小时。最近 7 篇日报的链接参与去重；不同媒体对同一消息的报道可能有不同链接，不做语义去重。全部来源抓取成功才发布，失败退出供定时重试；无匹配消息的栏目注明暂无消息。没有使用外部 AI、API key 或第三方付费服务，也未启用原生 RSS 逐条导入和 Automation。

## NAS 本地标题翻译

2026-10-08 接入专用翻译模型 `hf.co/tencent/HY-MT1.5-1.8B-GGUF:Q4_K_M`。模型文件约 1.13 GB；实测运行大小约 1.25 GB，`size_vram: 0`。NAS 配有 T400 2GB，本任务指定 `num_gpu: 0` 使用 CPU，不修改 Ollama 全局配置。

用户提供的 `http://192.168.50.28:11436/` 实际为 Open WebUI，底层 Ollama 监听 NAS 本机 `127.0.0.1:11434`。由 NAS 的 Python 脚本直接请求 loopback API，不新开端口、不引入 WebUI 登录凭据，仅发送公开 RSS 标题。

NAS 运行入口先让 Rails 返回待翻译标题，再在主机调用 Ollama `/api/generate`，最后调用 Rails 发帖。使用官方 HY 模板控制标记、1024 上下文、160 输出 token、temperature 0；模型短暂保留 2 分钟以便同批标题复用。译文缓存在主机 `/vol1/docker/discourse-preview/shared/state/acg-daily-translations.json`，容器读取同一文件 `/shared/state/acg-daily-translations.json`。缓存原子写入、权限 0600，主机 muwei 与容器 discourse 现场核验均为 UID 1000。

仅翻译标题，不抓取正文生成摘要。成功译文必须为单行、有中文、正常生成结束，并保留原文中的阿拉伯数字（英文序数如 2nd 可译为“第二”）。翻译失败或校验不通过时发布原文并注明翻译暂不可用；失败结果不缓存，下次可重试。译文仍可能误译作品名或人名，原文与来源链接一起保留，正文注明自动翻译仅供参考。

实测单条约 1–2 秒，首次加载约 4.85 秒；11 条真实海外标题的批次得到 10 条通过结果、1 条数字校验回退。该批次还发现一条英文成人标题漏过滤，已补齐英文关键词并验证从发布预览排除；验证材料保留在 `/shared/state/acg-daily-translation-validation-20261008T152336Z.json`。共享 Ollama 实例会切换当前加载模型，期间其他模型可能需要重新加载；没有承诺模型并驻或不影响其他推理请求。

`script/translate_acg_titles.py` 部署为 NAS `/home/muwei/discourse-docker-preview/acg-daily/translate_titles.py`，使用 Python 标准库，无新增 Python 依赖。主机锁 `acg-daily-translation.lock` 防止翻译流程并发，Ruby 发帖锁继续保留。同日已发布时整个流程直接退出。

## 运行与维护

本机源码：

- `script/acg_daily_bot.rb`：抓取、过滤、预览、发布及自检。
- `script/setup_acg_daily_bot.rb`：首次建账号与分区，先保存权限快照，已有对象时拒绝重复配置。
- `script/check_acg_daily_bot.rb`：权限、私有社团隔离和首篇日报检查。
- `script/run_acg_daily_bot.sh`：NAS 执行入口；必须在 NAS 使用，不在 Mac 本机执行。
- `script/translate_acg_titles.py`：NAS loopback Ollama 翻译、缓存和发帖编排；`--self-test` 不调用模型或真实发布。

容器中的运行文件保存于持久目录 `/shared/state/acg_daily_bot.rb`。NAS 入口为 `/home/muwei/discourse-docker-preview/acg-daily/run.sh`，由 NAS 用户 `muwei` 的 crontab 调用。NAS 系统时区现场核验为 `Asia/Shanghai`，cron 服务为 active。

```cron
0,15,30,45 12 * * * /home/muwei/discourse-docker-preview/acg-daily/run.sh >> /home/muwei/discourse-docker-preview/acg-daily/run.log 2>&1
```

12:00 首次执行，其后三次为失败重试；当天话题已存在时立即退出。锁文件 `/shared/state/acg-daily.lock` 避免并发发布。主机定时任务不依赖 Mac 或 Codex 保持运行。

```sh
# 自检，不连接数据库或网络
docker --context nas exec -u discourse app ruby /shared/state/acg_daily_bot.rb --self-test

# 手动触发；同一天重复运行不会再发帖
ssh nas /home/muwei/discourse-docker-preview/acg-daily/run.sh

# 权限检查使用事务内临时账号并回滚
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner /shared/state/check_acg_daily_bot.rb'
```

每日已发帖时脚本预览也返回现有话题。容器重建后须确认 `/shared` 持久挂载、运行脚本存在、容器仍名为 `app`。账号和分区随数据库保留。

## 验证与停用

已验证首篇真实发帖、公开站点的已登录 Chrome 页面、NAS 执行入口同日重跑无重复、内容过滤自检，以及黑箱动画社、黑光文学社、非社团成员与管理员的服务端权限。机器人不能访问两个私有社团；原有分区权限快照一致。临时验证账号已回滚。

来源扩充时另行通过多源合并自检（抓取全部来源、栏目上限、每条来源标注），并从 NAS 读取真实 RSS 生成 24 小时汇总预览；五个来源都出现在预览中。预览保存在 `/shared/state/acg-daily-sources-preview-20261008T150421Z.json`。旧运行脚本保存在 `/shared/state/acg_daily_bot-before-sources-20261008T150502Z.rb`；需要回退时只恢复该文件到 `/shared/state/acg_daily_bot.rb`，不更改 cron 或数据库。新增源从下一篇日报参与汇总，未重写首篇日报。

本地翻译接入保留 Ruby 旧版 `/shared/state/acg_daily_bot-before-translation-20261008T152358Z.rb` 和 NAS 旧入口 `/home/muwei/discourse-docker-preview/acg-daily/run-before-translation.sh`。关闭翻译时恢复这两个文件，保留五个订阅源、缓存、模型和日报数据。不要用更早的来源扩充备份替代翻译前备份。模型是否继续保留由其他使用者及用户决定，不自动卸载。

翻译与回退自检、真实模型推理、缓存读取及 Discourse 正文渲染均通过。真实预览保存在 `/shared/state/acg-daily-translated-preview-20261008.json`，两个栏目共 12 条来源链接、9 条带译文和原标题。已验证更新后的主机入口同日退出，不重复发帖；初次接入时首篇日报未改写。测试结束后重新加载原有 `qwen3.5:0.8b-gpu`，API 回读 `size_vram: 872478145`。未等待下一次定时翻译和发布，不将预览称为已发布。

随后用户明确要求翻译今日已发布日报：使用同一 HY-MT1.5-1.8B 模型翻译话题 70 首帖（Post 88）的 6 条英文标题，通过 PostRevisor 更新原帖，保留每条原文和全部 12 个来源链接。针对人名和 Crunchyroll Storyworks 部门名补做术语约束，并修正模型多出的作品名前缀。游戏栏目与成员回复保持原样。首帖最终版本为 3，已回读正文并用已登录 Chrome 验证显示。原文快照 `/shared/state/acg-daily-post-70-before-translation-20261008T153056Z.json`，译文记录 `/shared/state/acg-daily-post-70-translations.json`；快照用于定向恢复首帖，不覆盖话题回复。页面截图保存在本机 `outputs/acg-daily-post-70-translation/updated.jpg`。

定时规则已安装并回读，下一次 12:00 自动触发尚未发生，不能把手动调用入口说成已验证 cron 的实际触发。未验证真实学生登录、每个外链可用性或邮件通知。`bin/lint --fix` 因本机旧 Ruby 缺少 `Array#filter_map` 无法运行；使用生产 Ruby 自检、语法检查和实际 Rails 发帖验证。

停用时只移除 `muwei` crontab 中标记 `blackroom-acg-daily` 的注释与 `/acg-daily/run.sh` 对应行，保留其他任务。无需停容器或删除业务数据。原 crontab 快照：`/home/muwei/discourse-docker-preview/acg-daily/crontab-before-20261008T145025Z.txt`；配置前权限快照：`/shared/state/acg-daily-before-20261008T144616Z.json`。不要整体恢复快照覆盖后来新增的任务或权限。账号、分区和已发布日报保留；删除这些对象需另行授权。
