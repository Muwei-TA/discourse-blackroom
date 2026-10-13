# 游戏接入与 MCP 管理

更新于 2026-10-13。当前生产游戏目录为分区 53、弹球 `bonk`（话题 158）、绘画 `skribbl`（话题 159）；本次已通过生产 Rails 回读确认。用户批准后，游戏 MCP 扩展已持久化安装并启用，全站工具为 38 项。ChatGPT 管理连接已刷新并实际显示两新工具（38 项）；discobot 连接显示游戏查询（18 项），不含管理员接入准备工具。

## 平台职责

论坛提供目录、说明讨论和成员身份门禁。浏览器点击原生 CSRF POST 按钮后，在新标签页经单次短期票据进入对应游戏网关。每款游戏有独立网关和内部游戏容器；网关代理 HTTP 和 WebSocket，定期复核论坛会话。游戏自行负责房间、玩法、同步和计分。平台不创建玩家容器、不提供统一匹配、排行榜、云存档或游戏内部用户映射。

符合现有接入契约的游戏可以独立构建、更新和回退。重启游戏可能丢失内存房间；数据库或磁盘存档需由游戏自身持久化。完整部署和既有验收边界见 [games.md](games.md)。

## 新游戏接入

1. 提供构建产物或容器镜像、监听端口、玩法说明、公开域名、实时连接路径及邀请参数。纯静态游戏也可使用静态服务容器，`websocket_paths` 为空数组。
2. 游戏必须兼容独立域名的根路径、静态资源与 Host/Origin。当前平台邀请只透传 `room`，允许 1–80 个字母、数字、下划线或连字符；其他邀请参数需要另行适配。门禁不会自动将论坛用户变成游戏内昵称或存档账号。
3. 在现有游戏分区创建管理员治理的说明话题，回读真实 topic ID。机器人内容统一用原生 discobot。
4. 在非敏感 `games.json` 清单追加游戏，保留原有条目。每款游戏字段为 `id`、`title`、`description`、`origin`、`upstream`、`websocket_paths`；另外维护 `{category_id, topic_ids}` 原生对象映射。
5. 复用 `services/blackroom-games-gateway/config.mjs` 的 `renderConfigs` 和 `script/games-release/prepare.mjs` 的 `prepareRelease`，生成论坛及单游戏网关私有配置。密钥由受保护文件提供，不由 MCP 读取或返回。
6. 获得具体部署与公网开放授权后，准备 NAS 回退材料，部署该游戏的内部 backend 网络、通用网关实例、独立域名路由和 TLS。游戏源站不开放可绕过门禁的宿主机端口。
7. 检查匿名拒绝、成员启动、资源和实时连接、邀请同房、真实玩法及注销/封禁撤权，再开放目录。目录组件循环渲染清单，新条目无需新增页面组件；现有封面样式仅覆盖 bonk/skribbl，新封面需补主题资源和对应样式。

供管理员准备的新条目示例（仅示例，尚未登记或部署）：

```json
{
  "id": "my-game",
  "title": "我的网页游戏",
  "description": "玩法简介",
  "origin": "https://my-game.muwei.xyz",
  "upstream": "http://my-game:3000",
  "websocket_paths": [{ "path": "/ws", "match": "exact" }]
}
```

## MCP 扩展

源码为 `plugins/blackroom-mcp-games/`，依赖现有 `BlackRoomGames` 插件及 Discourse 原生 MCP，不新增依赖、数据表、站点设置或 OAuth scope。

| 工具 | 权限与结果 |
| --- | --- |
| `discourse_list_games` | `mcp:content:read`；检查正常成员状态、游戏分区及说明话题可见性，返回游戏简介、讨论链接和浏览器入口；不返回服务密钥、票据或内部上游 |
| `discourse_prepare_game_registration` | 管理员且有 `mcp:site-settings:read`；检查新 ID/域名、地址格式、WS 规则、可选话题归属与重复映射，返回清单条目、论坛条目和部署检查步骤 |

准备工具是无副作用的 dry run：`status=prepared`、`applied=false`。不联网探测提供的地址、不创建话题、不写配置、不启动容器、不修改 DNS 或公网访问。未提供 `topic_id` 时返回 null，必须先取得真实话题 ID 才能生成实际配置。格式验证不证明域名所有权、服务可达性或游戏可玩性；这些由授权后的部署验收确认。MCP OAuth 身份不会代替玩家的浏览器登录会话。

安装需要将扩展放到 NAS 持久目录，添加对应 launcher `after_code` 恢复链接，在加载后只启用这两个 `McpPrimitive`，平滑重载 Web 进程，再刷新客户端工具目录并实际调用。停用只关闭两工具并撤销本扩展链接，不改既有游戏平台。生产安装前保留配置及插件副本在 `/vol4/1000/backup/blackroom/game-releases/`；本次安装已获得用户授权。

验证脚本 `plugins/blackroom-mcp-games/check.rb` 在隔离论坛通过原生 `tools/call`，检查合法查询、管理员准备、scope 和管理员门禁、非法及重复输入、静态游戏、停用工具拒绝以及配置文件未改变。数据库策略与审计记录在事务中回滚；脚本不发帖、不创建成员、不发行游戏票据。使用 `discourse` 用户、隔离论坛和正确 `BLACKROOM_GAMES_CONFIG` 运行。真实客户端目录刷新及生产调用另行验收。

## 生产验收与回退记录

2026-10-13 安装在 NAS `/vol1/docker/discourse-preview/shared/state/blackroom-mcp-games`，运行插件为 `/var/www/discourse/plugins/blackroom-mcp-games` 的软链接。launcher `after_code` 追加该链接恢复命令，前后 YAML 解析值比较确认只有这一 hook 增量。Resend 持久源与运行副本 SHA-256 一致。使用 `sv 2 /etc/service/unicorn` 触发 launcher 的 USR2 平滑重载；重载期间一次 HTTP 验收返回 503，健康恢复后目录及两工具真实 HTTP 调用通过，不能把此次重载称为零中断。

通过原生 `McpPrimitiveUpdater` 只追加两工具。原工具 enabled/emergency_blocked 和群组 scope 快照比较未变化，游戏私有配置 SHA-256 未变化。真实 HTTP 验收复用管理员已有授权范围签发五分钟测试 token，不读取旧 token，结束后撤销；读取实际 bonk/skribbl 目录及生成静态游戏草案成功，`applied=false`。这是生产服务端 HTTP 调用和客户端目录验收，没有向另一个 ChatGPT 聊天发送模型测试消息。本聊天工具 schema 尚未动态增加两工具。

两个游戏及两个网关容器 ID 保持一致，未重启；论坛容器 ID 也保持一致。隔离 24 项原生 MCP 检查与 lint 通过。证据在 `outputs/games-mcp-20261013/`。

NAS 回退集合为 `/vol4/1000/backup/blackroom/game-releases/games-mcp-20261013-online/`，包含 `app.yml.before`/`after`、MCP 策略快照、插件、真实 HTTP 摘要、当前程序镜像及含上传的原生备份。更新前备份 45,660,190 字节，SHA-256 `fbb577777678d2858eb8e4f7bc0c5cba0248c461182e7479126155563c2fb89d`，异卷副本一致、数据库与上传条目存在、归档可读。镜像为 `sha256:f3c7d1c4b9c34707a393615a4cd0ce68429cdae993d87296dc2f27f4cc17f011`，镜像归档 4,094,116,352 字节且可读。本次没有新执行数据库恢复演练。

回退先只关闭两工具；需卸载时移出本次插件软链接、从当前 launcher 配置中只撤销本次 hook（不要覆盖其他并发维护变更），再平滑重载 Web。保留源码和证据，不改游戏清单、容器、数据或既有 OAuth 授权。

按更新助手契约由 discobot 发布稳定教程 [173](https://discourse.muwei.xyz/t/topic/173) 与公告 [174](https://discourse.muwei.xyz/t/topic/174)，公告全站置顶至北京时间 2026-10-20 10:04:58。公告页面已核对作者、功能更新标签、教程链接和全站置顶；教程另行核对步骤及互链。

上线与公告发布后的完整备份为 45,684,175 字节，SHA-256 `56e481d097374cfd5618b77d736ef5398ff8d6b5700594f70b041c1d65133f1c`，NAS `forum-after.tar.gz` 与源备份一致且归档可读。教程浏览器回读含作者、使用指南标签、全部步骤及公告互链，console 未捕获 error。
