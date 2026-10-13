# 游戏板块测试环境与验收

更新于 2026-10-13。本文保留隔离测试的历史证据；游戏平台已于 10 月 12 日晚正式上线，生产部署与证据边界见 [games.md](games.md)。辅助登录和合成身份只用于隔离测试，不能带入生产。

## 使用入口

这台 Mac 上打开 `http://forum.games.localhost:18190/__games_test/login/player_a`，使用合成测试成员进入游戏目录。该辅助入口只存在于回环桥，不使用或读取真实成员凭据。点击游戏说明中的「在新页面开始游戏」打开独立游戏页，原论坛页保留。游戏默认只支持桌面端。

本机桥由 `python3 script/games-test/local-bridge.py` 运行，监听 127.0.0.1 的 18190/18192/18193，经 `ssh nas` 连接 NAS 内部网络。启动命令应在本 worktree 执行；端口已有监听时不重复启动。NAS 的测试容器无发布端口、无外网连接、restart=no。当前 NAS 测试目录为 `/home/muwei/docker-apps/blackroom-games-test-20261012`。

## 早期隔离同步记录（历史）

以下为早期隔离同步时的镜像快照，不是当前生产镜像；正式切换使用的 d728/dbcff 镜像完整摘要见 [生产运维记录](games.md)。本次正式接入没有升级游戏版本，原 3001/3002 宿主机入口已经撤除。

| 游戏 | 精确镜像 |
| --- | --- |
| 黑房弹球 | `sha256:05780481cd8c42a09d2292a48ca40901bde6c1a9dc0ab300e6db3a15f4b85d8f` |
| 你画我猜 | `sha256:f079321f7dfb66d773fe069ed4c29c7e7a2ae62d2a76f02ba6a907d4151b80e2` |

两个原始游戏在用户更新后 ID 已改变；本次同步前另存 `baseline-after-user-game-update.json`，以此核对同步后的现场。先前测试容器停止并改名为 `*-before-sync`，保留原镜像供测试回退；未修改或重启原端口容器。

## 早期隔离验收结果（历史）

| 层级 | 结果与边界 |
| --- | --- |
| 原生成员权限 | 合成社团 A、社团 B、非社团正常成员、管理员均可启动两款游戏；私有社团保持隔离。匿名、未激活、封禁、会话过期/撤销、跨游戏票据、错误状态、过期/重放票据均拒绝。 |
| 新页面 HTTP | 四类合成成员通过原生登录 Cookie、CSRF 表单打开 nonce CSP 过渡页，POST 兑换并 303 进入游戏；房间参数保留，缺失 CSRF 和重复票据失败。 |
| 网关回归 | HTTP/WS 门禁、Host/Origin 校验、API 与论坛凭据过滤、畸形请求目标拒绝且进程存活、握手后空闲连接、并行验证超时断连均通过。 |
| 双成员真实游戏服务 | 两个不同合成成员、独立原生论坛会话，经过实际插件与网关：弹球同房间加入、移动同步、回合结束、比分 0:1；绘画轮流选词、画线同步、两人猜词、终局比分 749:749。属于协议自动化，非两名真人实玩。 |
| 桌面浏览器 | 实际点击/键盘打开独立页面，原论坛保留；两个浏览器页加入弹球房间，开始比赛并操作移动/跳跃/防御；绘画邀请加入、鼠标拖动画线、另一页中文猜词、得分与终局可见。浏览器双页共用合成成员登录状态；不同成员身份由上行协议验收覆盖。 |
| 原生注销 | `DELETE /session/player_c` 后既有游戏 WS 在 51,156ms 内关闭。 |
| 封禁 | 仅临时封禁合成 player_c，既有 WS 在 40,172ms 内关闭，之后 HTTP 401；已恢复该合成账号。 |
| 代码检查 | 定向 ESLint/Prettier/RuboCop/SyntaxTree/Stylelint、主题字段编译、Node 测试/语法与 Python 编译通过。运行镜像缺少 RSpec 执行依赖，未声称 RSpec 全套通过。 |

`outputs/games-test/gameplay.json` 与 `suspension.json` 保存可回读结果；`bonk-new-page.jpg` 与 `skribbl-new-page.jpg` 是实际浏览器截图。旧 `bonk-embedded.jpg` 仅保留此前内嵌方案的历史证据，不能代表当前体验。

浏览器测试中曾重复激活「加入房间」，新版游戏正确拒绝重复加入并提示「请先退出当前房间」；后续正常游戏和计分通过。当前截图选用无该提示的另一玩家页面。

## 复测

在 worktree 中运行：

```sh
node --test services/blackroom-games-gateway/*.test.mjs script/games-release/prepare.test.mjs
python3 script/games-test/check-bridge.py
node script/games-test/check-gameplay.mjs
node script/games-test/check-revocation.mjs
```

后两项要求本机桥运行、NAS 合成身份与插件配置已准备，且测试脚本已同步到 NAS。`check-revocation.mjs` 只操作有匹配私有 fixture ID 的 player_c，finally 恢复封禁状态。测试凭据、服务 key 与授权 Cookie 只在测试主机/进程内使用，不写到 Git 或结果文件。

NAS 实际 HTTP 启动矩阵：

```sh
ssh nas python3 /home/muwei/docker-apps/blackroom-games-test-20261012/source/script/games-test/check-new-page.py
```

原生权限断言需要以 discourse 用户运行 `script/games-test/check-authorization.rb`，设置 `RAILS_ENV=production` 与 `BLACKROOM_GAMES_CONFIG=/shared/state/blackroom-games.json`；容器必须是 `blackroom-games-test-20261012-forum`。`create-environment.py` 只提供首次隔离资源准备，不是生产安装器或完整一键部署。

## 维护与回退

源码在隔离 worktree，NAS 保留测试源码、数据卷、私有配置与两个旧测试容器。主题可重新导入，插件和网关源码挂载只读。停止本机桥即可关闭本机测试入口，不触碰生产。若停止测试容器，务必精确使用测试前缀，不删除数据卷；游戏内存房间不会在容器重启后恢复。

10 月 12 日生产切换已经完成：固定 HTTPS 来源、Pangolin/Newt 转发、网关门禁及原 3001/3002 端口收紧已落地，正式教程 160 与公告 161 已发布。上述隔离脚本本身不负责生产发布，也不能修改正式账号或生产配置。

## 正式候选与生产验收增量

| 层级 | 已有结果 | 不能据此宣称 |
| --- | --- | --- |
| 隔离候选 | 3 个合成身份的独立原生会话；角色门禁、房间创建/指定加入/隔离、两款游戏协议对局通过 | 两名真实学生已独立登录验收 |
| 隔离撤权 | 注销后 50,295ms、封禁后 37,452ms 收回连接；测试账号恢复 | 随意封禁生产学生账号是验收必要步骤 |
| 协议容量 | 同时弹球 8、绘画 12 个自动化客户端，约 31.583 秒工况，无 OOM/重启 | 20 名真人、长期容量或全站并发上限 |
| 生产桌面 UI | 同一真实管理员多标签：弹球两房后指定加入、键盘对局比分 0:1；绘画邀请、鼠标绘画同步、中文猜词和终局 194/250 | 多个独立真实成员或学生身份已验收 |
| 生产门禁 | 公共 TLS、授权后的实际游戏流程；匿名 HTTP/静态资源/polling 401，旧 IPv4/LAN/IPv6 端口拒绝连接 | 单靠健康端点已完成所有业务验收 |
| 运行观察 | NAS 原生每 5 分钟观测已运行，最近回读 OK | 已完成 24 小时稳定性观察 |
| 恢复材料 | NAS 归档可读、镜像加载与隔离插件链接安装/撤销通过 | 新完整数据库恢复演练通过 |

实际音频硬件未听验；手机 UI/触摸按用户要求排除。10 月 13 日另行完成两张封面渲染与目录一次点击新标签直达两款游戏首页的生产 Chrome 验收，原目录保留、console 无捕获 error。隔离四角色 × 两游戏共 8 次合法启动检查实际 style/script nonce 与响应 CSP 匹配，CSRF/Origin/非法房间/重放负例拒绝。公告 171 和修订后的稳定教程 160 已完成作者、标签、步骤、互链及置顶浏览器回读；证据见 `outputs/games-release/games-direct-launch-20261013/` 与 `outputs/blackroom-updates/games-direct-launch-20261013/`。
