# BlackRoom 游戏平台运维

更新日期：2026-10-13，北京时间。游戏平台已于 10 月 12 日晚接入正式站点并开放正常成员入口，教程 [160](https://discourse.muwei.xyz/t/160) 与公告 [161](https://discourse.muwei.xyz/t/161) 于当晚发布。相关契约见[接入说明](games-integration-plan.md)和[正式上线计划与执行结果](games-production-release-plan.md)。上线事实与真人验收、完整恢复演练、24 小时观察分别记录，不能互相替代。

2026-10-13 后续已部署第三款「茶绘」至 `drawpile.muwei.xyz`，复用目录、说明和成员网关；说明话题 175，独立客户端／网关、原服务端和网络见 [茶绘接入记录](drawpile.md)。正式 Chrome 的建房、邀请、昵称、双向绘画和聊天通过；系统文件保存待桌面解锁后完成，更新公告尚未发布。现有两个游戏及网关容器未重启，指南 160 仍保留现有地址。NAS 五分钟观测已增加茶绘三容器与 `.5:8080` 匿名拒绝目标。

## 部署与访问

游戏平台入口固定为 `https://discourse.muwei.xyz`。论坛的其他别名保持原有用途，游戏入口跳回默认来源；不复制跨域登录 Cookie。游戏以新页面打开，论坛负责目录、讨论和成员授权。

| 对象 | 生产位置或标识 |
| --- | --- |
| 游戏分区 | 分区 `53`；正常成员可见、可回复，staff 创建目录话题 |
| 黑房弹球说明 | 话题 `158`；`https://bonk.muwei.xyz` |
| 你画我猜说明 | 话题 `159`；`https://skribbl.muwei.xyz` |
| 主题组件 | `BlackRoom Games`，Theme `6`；已编译并关联正式父主题 `-1`、`-2`，侧栏入口已生效 |
| 平台源码 | NAS `/home/muwei/docker-apps/blackroom-games-platform/source` |
| 非敏感清单 | NAS `/home/muwei/docker-apps/blackroom-games-platform/games.json` |
| 网关私有配置 | 平台目录 `private/gateway-bonk.json`、`private/gateway-skribbl.json`；含密钥，不进 Git、不输出正文 |
| 插件持久目录 | NAS `/vol1/docker/discourse-preview/shared/state/blackroom-games` |
| 容器内插件 | `/var/www/discourse/plugins/blackroom-games` → `/shared/state/blackroom-games/plugin` |
| 论坛私有配置 | `/shared/state/blackroom-games/forum.json`，UID `1000`、模式 `0600` |
| 未来重建持久化 | launcher `after_code` hook 恢复上述插件软链接；不能只检查 YAML，须回读实际链接和插件加载 |

当前网关实例为 `blackroom-games-gateway-bonk`、`blackroom-games-gateway-skribbl`，游戏实例分别为 `blackroom_bonkio-game-1`、`skribblrsio-skribblrs-1`。所有 Docker 运维明确使用 `docker --context nas`；NAS 本机脚本明确使用 Unix Docker socket。

| 网络 | 地址范围 | 接入范围 |
| --- | --- | --- |
| `blackroom-games-ingress` | `172.16.243.0/28` | 两个网关与 Newt；弹球网关 `.2:8080`，绘画网关 `.3:8080`，Newt `.4` |
| 弹球 backend | `172.16.243.16/28`，internal | 仅弹球和对应网关 |
| 绘画 backend | `172.16.243.32/28`，internal | 仅绘画和对应网关 |

Pangolin 弹球资源为 `boiling-gunnisons-prairie-dog`，绘画资源为 `unwitting-eastern-bearded-dragon`。两个新增资源已关闭 Pangolin SSO，应用门禁由各自网关承担；这不改变其他资源的 SSO。证书签发及公网 TLS 已成功；10 月 12 日正式浏览器已通过授权进入两款游戏并完成对局，身份范围见下文。

原游戏 Compose 已移除 `ports` 并连接各自 external backend 网络。原 `3001`、`3002` 的 IPv4/LAN/IPv6 直连检查均无法连接；匿名访问内部网关、使用正确登记 Host，返回 `401`。游戏每实例限制为 1 CPU、512 MiB、128 PID，并启用日志轮转。网关每实例为 0.5 CPU、256 MiB，UID 1000、只读文件系统，不发布宿主机端口。Newt 不接入游戏 backend。

## 配置与鉴权契约

清单字段为 `forum_origin`、`forum_internal`、`category_slug`、`games[]`。每款游戏登记 `id`、`title`、`description`、`origin`、`upstream`、`websocket_paths`；WS 规则仅支持 `{path, match: "exact" | "prefix"}`。ID 与 slug 使用 `^[a-z][a-z0-9-]*$`。公网来源必须是无凭据的规范 HTTPS origin，上游来自管理员配置，成员不能注册任意目标。

`services/blackroom-games-gateway/config.mjs` 的 `renderConfigs(manifest, forumState, gatewayKey)` 返回 `{forum, gateways}`。`forumState` 固定为 `{category_id, topic_ids: {game_id: topic_id}}`，ID 必须来自实际原生对象回读。论坛配置包含目录与服务认证 key，目录条目不含上游或密钥；网关配置按游戏拆分，每实例 `games` 长度必须为 1。

启动票据通过 POST 传递，60 秒内单次原子消费，不写 URL。网关签名 Cookie 绑定游戏、来源及有效期，生产采用 Secure、HttpOnly、host-only、SameSite=Strict；伪造、过期、跨游戏 Cookie 在本地拒绝，不查询论坛。游戏源站不接收论坛 Cookie、服务 key、API 身份及伪造转发头。

同一授权的并发验证合并；每网关验证并发上限 4、排队上限 1 秒、请求超时 4 秒。已建立 HTTP、polling 与 WS 都在周期复核范围；默认每 15 秒检查，失效或认证服务不可用时关闭连接，验收上限为 60 秒。启动入口可见、HTTP 200、WS 握手成功均不能替代真实游戏验收。

## 平台与游戏独立更新

平台仅依赖登记 origin、根路径和静态资源、HTTP/WS 路径、Host/Origin 兼容性及邀请参数。房间 ID 是不透明值，平台只检查边界并透传，不创建房间、不自动匹配、不维护平台房间列表。

游戏自身负责建房、加入、容量、开始、猜词/绘画、比分与房间隔离。打开首页不自动加入已有房间；点击创建产生新房间，房间码/邀请加入指定房间。不存在、满房或已开始的错误由游戏处理，不自动转入另一容器。

在接入契约保持兼容时，某款游戏可自行构建、部署和回退，不要求发布论坛插件、主题或网关，也不要求同步更新另一款游戏。重启该游戏可能结束其内存房间；其他游戏及论坛继续使用。接入契约变更才修改清单，并定向复测入口、邀请、HTTP/WS 与门禁。

本次网络切换没有升级游戏镜像。以下为本次发布快照，不是将游戏与平台版本永久绑定：

| 对象 | 镜像 |
| --- | --- |
| 网关 | 10 月 12 日 `sha256:5c139946edef625eb092267b397c4c215f135e6cb0bebfba423e2c817164765b`；10 月 13 日用户名接入后见下节 |
| 弹球 | 10 月 12 日 `sha256:d728479da42b326c371e9665b9ac73d717a87fbfd1258e1240e28102fb3d6d3e`；10 月 13 日用户名接入后见下节 |
| 绘画 | 10 月 12 日 `sha256:dbcff9b944296ae3fdb810ad099ade0c25d9c49fb18b5cf77e2e19051ba5a20e`；10 月 13 日用户名接入后见下节 |

## 备份与定向回退

NAS 回退材料位于 `/vol4/1000/backup/blackroom/game-releases/games-20261012`。本次已检查归档可读，并验证保存镜像加载及隔离插件持久软链接的安装/撤销。此结论不等于执行了完整生产数据库恢复，也不代表能够恢复重启前的游戏内存房间。

认证绕过、旧源站仍可匿名访问、撤权超过 60 秒、论坛基本功能故障或反复 OOM/重启时，先停止开放受影响入口并保留日志、容器数据、源码和镜像。

1. 单游戏故障：关闭对应公网资源/网关入口，保留内部游戏数据；用已保存的该游戏或网关版本定向恢复，只重启受影响实例，再验收其契约。
2. 共有鉴权故障：关闭两个游戏入口，在私有论坛配置中撤下登记，并收回现存连接；普通论坛功能应保持可用。
3. 入口界面故障：解除游戏主题组件关联及侧栏入口，保留分区、说明话题、成员回复。插件故障按备份定向撤销本次链接/源码并执行必要的最小进程重启。
4. 正常回退不覆盖整个论坛数据库。本功能没有数据库迁移；生产数据恢复需要独立具体授权和恢复方案。
5. **不得把原 `3001`/`3002` 恢复为匿名 LAN/公网入口作为默认回退。** 未获该范围的授权时，维持维护状态。

恢复后检查实际运行镜像、网络、插件链接与加载结果、配置权限，再检查论坛登录/普通话题/代表性图片/私有分区和既有邮件适配器。保留旧制品及失败证据，不把删除容器当作删除卷，也不把旧容器称作完整备份。

## NAS 原生观测

脚本为 `script/games-release/check-runtime.py`，仅使用 Python 标准库。每次只检查上述精确 5 个容器的运行、OOM、重启计数、镜像与资源限制/使用量，并检查论坛 `/srv/status` 返回 200、两个网关使用正确 Host 的匿名请求返回 401。不读取完整 inspect、环境变量、凭据或 HTTP 响应正文，不执行重启或外部通知。

显式输出目录包含 `status.json` 和 `changes.jsonl`，文件权限均为 `0600`。最新使用量每次刷新；正常 CPU/内存使用量波动不追加日志，状态变化或错误才追加。重启计数相对上一轮上升会报告错误。首次运行只建立基线，不能推断此前是否重启；脚本也不能判定真实页面、WSS 或多人游戏是否正常。

由 NAS 运维用户安装，在已确认其 Docker socket 权限后先手动执行：

```sh
python3 /home/muwei/docker-apps/blackroom-games-platform/source/script/games-release/check-runtime.py \
  --output-dir /home/muwei/docker-apps/blackroom-games-platform/runtime
```

手动检查通过后，可安装以下 NAS 原生 cron 示例（部署时核对 `python3`、`flock` 实际路径并创建受保护输出目录），每 5 分钟运行一次；flock 避免任务重叠：

```cron
*/5 * * * * /usr/bin/flock -n /home/muwei/docker-apps/blackroom-games-platform/runtime/check.lock /usr/bin/python3 /home/muwei/docker-apps/blackroom-games-platform/source/script/games-release/check-runtime.py --output-dir /home/muwei/docker-apps/blackroom-games-platform/runtime >/dev/null 2>&1
```

NAS 原生每 5 分钟观测已安装并开始采样。2026-10-13 00:10:12 +08:00 的状态回读为 `ok=true`、`errors=[]`，论坛 HTTP 200、两个网关匿名 HTTP 401。此为最近一次已回读样本，24 小时观察尚未完成；不能由采样正常推断期间所有真实游戏会话无故障。`changes.jsonl` 尚无自动轮转，首个 24 小时结束时检查大小并将需要保留的记录归档到上述 NAS 发布目录；持续高频错误应及时处置。

## 验收与待补证据

10 月 12 日生产 Chrome 验收使用同一真实管理员身份的多个标签页：弹球分别创建两间房，再指定加入同房，实际键盘操作后比分为 `0:1`；绘画分别建房再通过邀请加入，鼠标画线同步、中文猜词和终局比分 `194/250` 已可见。正式主题关联、侧栏入口、成员开放以及教程 160/公告 161 已完成，不再列为待发布动作。历史公告日期为 10 月 12 日晚，不能改写为 13 日的新公告。

隔离验收另有 3 个合成身份、不同原生会话，覆盖角色门禁、房间隔离与同时弹球 8/绘画 12 个协议客户端的工况。该工况运行约 31.583 秒，无 OOM/重启；这是 20 个自动化连接，不是 20 名真人。注销、封禁的隔离连接收回分别为 50,295ms、37,452ms；与正式管理员浏览器证据分开报告。

尚未完成两名真实学生独立参与验收，音频硬件输出未由人实际听验，24 小时观察尚未结束。备份归档可读、镜像加载以及隔离插件链接安装/撤销通过，不等于新执行了完整生产数据库恢复演练。手机 UI/触摸仍不在范围内。

## 10 月 13 日封面与直接启动

主题 assets 已导入两张独立生成的 2:1 PNG 封面，`bonk_cover` 和 `skribbl_cover` 由原生主题上传变量提供。目录主按钮使用原生 CSRF POST，在新标签页直接通过授权进入游戏；旁边保留“玩法说明与讨论”。别名目录转至默认平台入口，不跨域提交 Cookie。过渡页的 CSS 和脚本使用与响应 CSP 匹配的 nonce，加载动画支持减少动态效果偏好，并保留手动继续按钮；不会人为延迟跳转。

正式 Chrome 已从目录分别一次点击进入 `https://bonk.muwei.xyz/`、`https://skribbl.muwei.xyz/`，原论坛页面保留，两张封面正常显示，目录 console 未捕获 error。主题 6 共有 9 个字段（含两张上传资源）、父主题 -1/-2，编译错误为空。本次仅平滑重载论坛 Web 进程，未重启游戏或网关容器；重载后 NAS 检查正常。截图与生成提示词见 `outputs/games-release/games-direct-launch-20261013/`。

独立测试论坛的四个合成角色对两款游戏共 8 次合法启动，实际响应的 style/script nonce 与 CSP 精确匹配；缺少 CSRF、错误 Origin、非法 room、票据重放均拒绝，合法邀请参数保留。这是隔离 HTTP 检查，和生产 Chrome 一键启动证据分别记录。

板块介绍 157 已同步新步骤。按当前更新助手契约由 discobot 发布公告 [171](https://discourse.muwei.xyz/t/topic/171)，并修订稳定教程 [160](https://discourse.muwei.xyz/t/topic/160)；浏览器已核对作者、标签、步骤、双向链接和公告全站置顶。历史公告 161 保留。发布后原生备份含上传文件，NAS `post-launch-forum-backup.tar.gz` 为 45,303,438 字节，SHA-256 `15cb2d4be36e615e2f3ac3fb861cfcce1b1fb3ca4167587252bef50031f547fb`，归档可读；这不增加完整恢复演练的结论。

## 10 月 13 日默认站点用户名

论坛新增网关专用 `POST /blackroom-games/profile`，复用有效 grant/game、原生 token、账号状态与 Guardian 检查，实时读取当前 `username`。原 verify 仍返回 204。游戏网关提供同源 `GET /_blackroom/me`，只返回 `{username}`，设置 no-store，不开放 CORS；匿名、过期及跨游戏授权拒绝，不透传论坛 Cookie 或服务 key，不改写游戏 HTML。

两游戏首次打开或刷新时默认站点用户名，仍可手改，已有输入或实际建房/加入不被迟到资料覆盖。绘画同步输入框与实际 Socket.IO 玩家对象，昵称上限为 32 个 Unicode 码点，其他字段验证保留。为防止换账号快速建房使用前一人昵称，绘画不再自动使用 localStorage.name，原缓存数据保留；资料缺失或失败留空供手填，不改变成员门禁。

| 对象 | 当前用户名版本镜像 | 源码提交 |
| --- | --- | --- |
| 通用网关 | `sha256:22842257ca30514130f18e35d69fc5ce62dd7841eeefdc23ed0f9c0125597c82` | 平台 `28d896b37d`，检查 `95ad9df9cf` |
| 弹球 | `sha256:361af9183b796f32624e5c2886c97698d9053f04b45fd00de9260c013a74e812` | 独立源码 `9b49f467853f430ce08cc7eb6bc712c7b3cc99bb` |
| 绘画 | `sha256:324a2d78bb45977bd6a0484e336736255e33de7ffe83de0a861d36ea513f114b` | 独立源码 `43ac66fa30af364cb0972967ac02e8b5c478fb5c` |

游戏开发源码分别位于本机 `/Users/muwei/Documents/Codex/blackroom-games-username-20261013/bonk`、`skribbl`；未放入 Discourse 程序，也未推送外部仓库。变更已同步原 NAS 游戏源码，Compose 保留原 build/network/resource 设置并登记上述发布镜像。平台和游戏仍分别构建、更新、回退；本次是增加接入契约能力，不将后续游戏版本与平台版本绑定。

发布前弹球后端连接为零；绘画在临时容器回环检查中确认 rooms=0、playing=0、players=0，检查会话已关闭。论坛 Web 平滑重载、网关和两游戏分别替换候选镜像，未迁移数据库、旋转密钥或改变公网/私有分区访问规则。实例 healthy，未发布宿主端口，NAS 检查 OK。

弹球 91 项测试、typecheck/build，绘画 51 项测试/lint及真实 Socket.IO Unicode 专项通过；平台 8 项 Node 测试及 Ruby 资料/配置/过渡页检查通过。隔离原生 A/B 会话的两游戏资料正确且匿名 401；实际浏览器默认昵称、弹球同房 A/B 名单、绘画手改 A 与默认 B 邀请名单通过。正式 Chrome 真实管理员的两首页默认 `牧维_站点管理员版`，弹球建房名单一致，绘画手改“昵称验收”后名单一致、刷新恢复默认；页面未捕获 console error。此为本轮昵称验收，没有重跑整局玩法或补做两名真实学生验收。

公告 [172](https://discourse.muwei.xyz/t/topic/172) 和稳定教程 [160](https://discourse.muwei.xyz/t/topic/160) 已发布/修订。NAS 本次回退目录为 `/vol4/1000/backup/blackroom/game-releases/games-username-20261013`，含变更前后源码/私有配置、游戏与网关镜像，归档已校验可读；发布后原生论坛备份包含上传文件。正常回退分别恢复受影响组件，不覆盖论坛数据库、不恢复匿名 3001/3002。新游戏在资料接口暂缺时可手填，旧游戏也不依赖新接口。备份可读不等于新完整数据库恢复演练。

## 10 月 13 日黑房桌游

第四款服务 ID `freeboardgames`，标题「黑房桌游」，来源 `https://boardgames.muwei.xyz`，说明话题 180，成员网关 `172.16.243.6:8080`。FreeBoardGames 独立部署和数据库/Redis保留；原匿名 3003 撤下，目录封面、昵称、邀请与代表性井字棋已在正式 Chrome 验收。论坛及原三款游戏没有重启，具体制品、备份和回退见 [黑房桌游接入记录](freeboardgames.md)。

为兼容其原生协议，清单可选字段增加 `invitation_path_prefix: "/room/"`、`invitation_locales: ["en","pt","de","fr","it"]`、`bearer_jwt_paths: ["/graphql"]`、`csrf_cookie_names: ["_csrf","XSRF-TOKEN"]`。验证器限定路径、语言与 Cookie 名字，独立网关按需启用；其他游戏默认策略未变。论坛凭据始终剥离；仅游戏自身指定凭据进入该游戏上游，原生 grant/Guardian 与周期撤权仍独立生效。
