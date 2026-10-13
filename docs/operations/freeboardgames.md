# 黑房桌游接入记录

更新日期：2026-10-13，北京时间。**已接入正式站点，目录启动、默认昵称、邀请同房、中文/emoji 改名、实时对局及胜负终局已通过正式 Chrome 验收。** 原匿名 `192.168.50.28:3003` 入口已撤下。公告发布与回读记录见本文收尾段。

## 范围与契约

当前 3003 实际运行 FreeBoardGames.org，来源提交 `41a0077b7e76c1050b28f67537f00705a9095ed5`，许可 AGPL-3.0-or-later。它已取代此前同端口的茶绘目录服务；茶绘仍独立通过自己的站点入口运行。

稳定 ID `freeboardgames`、标题「黑房桌游」、来源 `https://boardgames.muwei.xyz`，追加到游戏分区 53。保留弹球、你画我猜与茶绘三个目录条目、说明话题、主题组件 6 和各自容器。游戏源码、依赖和 PostgreSQL 数据不放入论坛程序。

工作副本 `/Users/muwei/Documents/Codex/blackroom-freeboardgames-20261013`，正式发布目录 NAS `/home/muwei/docker-apps/blackroom-freeboardgames-20261013`。游戏原部署 `/home/muwei/docker-apps/freeboardgames-20261013`，持久卷 `freeboardgames-20261013-postgres`。原数据库、测试房间和用户记录保留。

成员网关 `172.16.243.6:8080` 只连接现有 `blackroom-games-ingress` 和游戏的 internal `freeboardgames-20261013-private` 网络；Newt 不接入游戏 backend。正式切换已撤下 3003 的宿主端口和原 Nginx 的 edge 网络连接。只替换本游戏的 web、bgio、backend、Nginx 与新增成员网关，不替换数据库/Redis或其他游戏。

HTTP 与 WebSocket 都经成员门禁。WS 精确 `/graphql` 与前缀 `/socket.io/`，不放行其他 Upgrade 路径。游戏有独立 JWT，HTTP 只在精确 `/graphql` 转发规范 HS256 JWT，限定 payload 正整数 `userId`、`iat`；游戏服务负责验签。该形状检查不是签发者证明，JWT不能代替论坛 grant；原生登录、有效账号与 Guardian 访问权限仍逐次/周期核验。

仅游戏声明的 `_csrf`、`XSRF-TOKEN` Cookie 经 HTTP 代理；重复同名项剥离，其他 Cookie、论坛凭据和 WS Cookie 仍剥离。上游两项响应 Cookie 重建为无 Domain、Path=/、SameSite=Strict，正式 HTTPS 加 Secure，`_csrf` 另加 HttpOnly。CSRF Token 不匹配返回 403，不绕过验证。游戏原 Nest 异常处理在缺失 CSRF 时会退出进程，适配源码补了明确的 403 中间件响应。

邀请为 `/room/<id>` 和源码现有五种语言 `en/pt/de/fr/it` 的 `/<locale>/room/<id>`。成员网关提取允许格式的房间号，登录交接后进入统一 `/room/<id>`，由游戏恢复语言路由。未知语言、编码房间号、多段路径及任意 return URL 不予放行。

默认昵称从同源 `/_blackroom/me` 读取当前本站 username。绑定当前账号的 sessionStorage 保留本标签页游戏身份；fresh 页面默认恢复当前 username，当页可手改，不改论坛资料。旧 localStorage 不消费、不删除；换账号不能沿用上一人 JWT/昵称。前后端统一 1–32 个 Unicode 码点，支持中文与 emoji，禁止空白及控制字符，不静默截断。资料接口 5xx 时可使用全新内存身份手填；401/403 阻止进入。迟到请求不向新的身份写回。

正式游戏镜像提供受门禁保护的 `/source.tar.gz`，包含对应修改源码及许可，不含部署密钥、node_modules或构建输出。

## 已验证与制品

- 游戏针对检查 4/4，网关/配置/发布生成 15/15，运行观测脚本 2/2 通过。Next production、webpack server、Nest backend 均已构建成功。
- 四个原生隔离身份通过启动交接；缺少 CSRF、错误 Origin、非法房间、票据重放被拒绝；过渡页 CSP nonce 匹配。匿名页面资源、资料、GraphQL、Socket.IO 拒绝，四账号资料正确。
- 事务内权限检查包括正常成员、管理员、匿名及临时私有分区的本社团、其他社团、非成员；权限已回滚。
- 两个独立 Chromium context 对应 `player_a`、`player_b`：实际建房、邀请同房、默认昵称、改名「测试棋手😀」、开始对局、五次落子与胜负终局通过，未捕获 pageerror。证据 `outputs/freeboardgames-20261013/isolated-ui.json` 及双方终局截图。这不是两名真实学生验收。
- 已建立隔离 GraphQL WS 后封禁 `player_b`，连接从建立至断开共 36,139 ms（包括执行封禁前时间），小于 60 秒上限。测试成员已恢复。
- 五种语言匿名邀请均正确保留房间。PostgreSQL 为 UTF8；实际房间改名与广播包含中文/emoji。

| 组件 | 正式已部署 image ID |
| --- | --- |
| web 与 bgio | `sha256:42a4072099d77e6018ef0e1b90a96c0de46e63cbd4f88cdbd730c92c54bbc9ec` |
| backend | `sha256:75a4991dd73128ddd2d644b021b1e21501aad433e55e3e635e14a375f58b79ef` |
| 成员网关 | `sha256:4759d301242fb413c937c5b2c74f001bfa6a9de9001012ecf578f105abec50c7` |

最后语言兼容仅变更网关，已测镜像重新建立隔离连接并验证语言交接与实际撤权；游戏镜像没有变更。

`bin/lint --fix` 对独立工作副本没有匹配的 core linter，未宣称 core lint 覆盖。相关 JavaScript 使用 Prettier，SCSS 使用项目 Stylelint，Ruby 脚本语法检查通过；未向生产容器安装开发依赖。

## 回退与备份

NAS `/vol4/1000/backup/blackroom/game-releases/freeboardgames-20261013/before` 已保存 PostgreSQL custom dump、配置/源码、原游戏镜像、平台配置和源码、原 upstream archive/适配 patch，以及含上传文件的原生论坛备份。制品 SHA-256 校验通过，数据库 dump 可被 pg_restore 列出，论坛归档可打开；未做本次完整恢复演练。

切换前再次核对原游戏活跃连接，配置中保留原数据库及 Redis。维护时短暂中断本游戏连接；数据库保存的状态能否恢复按游戏自身行为验收，不以镜像归档代替游戏状态恢复。

正式回退先关闭仅桌游路由和成员网关，再定向撤下 `freeboardgames` 配置/封面入口，保留帖子、回复、玩家记录和卷。游戏组件回退使用原镜像并维持源站内部网络；不能把重新打开匿名 3003 当作默认回退，不覆盖论坛数据库。`game-compose.candidate.yaml` 已应用至原部署目录，真实运行镜像与隔离已测镜像一致。

## 正式上线验收

用户明确确认后创建 Pangolin 资源 `severe-brown-rat`，`boardgames.muwei.xyz` → NAS Site `http://172.16.243.6:8080`。仅该新资源关闭额外组织 SSO；成员网关仍保护页面、资料、HTTP 与 WS。Cloudflare 既有 `*.muwei.xyz` 记录复用，没有更改 DNS 或其他公网资源。

新增说明话题 [180](https://discourse.muwei.xyz/t/topic/180)，作者原生 discobot（-2），使用指南标签；完整清单保留原三个条目后追加 freeboardgames。主题组件 6 共 11 字段，父主题 -1/-2，编译错误为空；独立 2:1 SVG 封面与第四张卡片已显示。

正式 Chrome 从目录一次点击新标签页进入，原论坛页保留；默认「牧维_站点管理员版」进入实际玩家名单，第二独立游戏身份通过 HTTPS 邀请同房，改名「桌游验收😀」在另一客户端可见。开始井字棋后双向五步落子同步，A 显示获胜、B 显示失败。两个标签属于同一真实管理员账号，不等于两名学生。目录/gameA console error 为空，截图位于 `outputs/freeboardgames-20261013/production-*.png`。

原论坛及三款游戏/网关启动时间均未改变，没有重启这些容器。桌游的 PostgreSQL 与 Redis 仍为原容器；原数据库 3 间房保留，验收新增一间房。切换前 boardgame.io 监听端口的入站已建立 TCP 为 0，此为连接采样，不是房间计数。

匿名公网 `/_blackroom/me` 和内部网关源文件请求均为 401；原 3003 无法连接，Nginx source 容器无端口发布，只连接 internal private 网络。NAS 原五分钟观测已追加桌游七容器和 `.6:8080` 门禁目标，手动运行 OK；未创建 Codex 定时任务。尚未完成长期观察。

相关 JavaScript/Ruby/SCSS 和编译、隔离与正式验收的范围如上；未逐款测试全部桌游、手机、两名真实学生、容量压测、长期观察或完整恢复演练。

## 公告与指南

原生 discobot 发布公告 [181](https://discourse.muwei.xyz/t/topic/181)，位于网站反馈、带功能更新标签；复用教程 [160](https://discourse.muwei.xyz/t/topic/160) 追加桌游步骤，保留旧游戏正文、教程地址与成员回复。公告全站置顶至北京时间 2026-10-20 16:09:42，已有发布器负责取消原更新助手旧公告置顶。清单及正式验收记录为 `outputs/blackroom-updates/freeboardgames-20261013/`。

上线后镜像、源码/私有配置及 Compose 已归档 NAS 同发布目录 `after/`，SHA-256 与归档可读检查通过。发布后含上传文件的原生论坛备份已成功并复制到 `after/forum-backup.tar.gz`，SHA-256 校验及归档可读检查通过；此项仍不等于完整恢复演练。
