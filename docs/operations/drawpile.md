# 茶绘接入记录

更新日期：2026-10-13，北京时间。**已部署至正式站点，目录启动、WSS 建房、邀请、昵称、双向绘画与中文聊天已通过正式 Chrome 验收；实际文件保存尚待桌面解锁后完成，公告尚未发布。** 不以客户端“Download Complete”提示代替实际文件验收。

## 接入范围

稳定 ID 为 `drawpile`，来源为 `https://drawpile.muwei.xyz`。复用游戏分区 53、现有单次启动票据、成员网关和同源 `/_blackroom/me`；游戏程序不放入 Discourse。仅正常登录且有游戏板块访问权限的成员可玩，独立新标签页启动。

独立工作源码位于 `/Users/muwei/Documents/Codex/blackroom-drawpile-20261013`。NAS 发布源码位于 `/home/muwei/docker-apps/blackroom-drawpile-20261013`，原 Drawpile 服务由 `/vol1/1000/docker/dpserver/docker-compose.yaml` 管理。客户端源码对应 Drawpile `a468e915e2b40d0a2e789adb7c5a41d26fea9b7f`，原服务为 Drawpile server 2.3.0，协议 `dp:4.25.1`。

部署增加 `blackroom-drawpile-web`、`blackroom-games-gateway-drawpile` 和 internal 网络 `blackroom-games-drawpile-backend`（`172.16.243.48/28`）。网关加入现有 ingress，地址 `172.16.243.5:8080`，Newt 仅连接 ingress；源站不对公网连接器开放。旧 `3003` 目录入口与 `27750` 原生 TCP 入口已在正式切换时撤下；保留卷、目录、镜像及原配置。

## 契约与适配

HTTP 根路径服务浏览器客户端；唯一登记的 WS 路径为 `/drawpile-web/ws`，内部转发至服务器 27751。管理 API 不进入成员代理。客户端 CSP 限定同源连接；网关保留上游 CSP 并附加独立 `frame-ancestors 'none'` 策略，继续剥离论坛凭据和上游 Cookie。WASM 依赖的 COOP/COEP 响应头由独立客户端提供。

昵称完整读取当前 `username`，允许手改，不写入 URL 或论坛。保留 Drawpile 的 22 个 UTF-16 单元限制；超限需手改，不自动截断。资料接口失败时手填，早期手改和启动不被迟到资料覆盖，旧缓存不成为默认昵称。

官方稳定 WASM 的中文昵称字形缺失，最终制品改为从对应源码编译，并显式注册 SIL OFL 的 Noto Sans CJK SC。构建采用官方 Qt 6.7.2 multithread WASM SDK、Emscripten 3.1.50、Node 22.16.0 与 aqtinstall 3.3.0；启用 Asyncify，时间轴拖拽恢复标准 Qt API。源码构建和中英文实际名单／聊天显示、时间轴关键帧拖拽已通过。WASM 39,033,410 字节，assets 8,523,301 字节；对应源码和复现脚本通过受门禁保护的 `source.tar.gz` 随应用提供。

标准会话邀请使用本站 `/?id=…`，沿用平台登录交接，保持指定会话；客户端加入地址只使用自己的 WS origin。兼容粘贴本服务器的原生 Drawpile 标准邀请。房间密码仍属于游戏自身限制，不能替代成员认证；原生 Codes 邀请码扩展不在此次范围内。单字符别名加入时加上内部 `/` 前缀，适配 Drawpile 自动加入解析器，不放宽平台校验。

初始资源预算为服务器 1 CPU／512 MiB／128 PID，客户端 0.5 CPU／128 MiB／64 PID，网关 0.5 CPU／256 MiB／64 PID。服务器限制 4 个会话、每会话 8 人、32 MiB 会话数据，采用非持久会话。最后一人离开会关闭会话，退出前应保存画作；镜像回退不能恢复活跃画布。

## 已有隔离证据

- 4 个独立原生测试角色完成启动交接；CSRF、错误 Origin、非法 room、票据重放拒绝，CSP nonce 匹配；匿名资源、资料接口和 WS 路径拒绝。
- `player_a`、`player_b` 两个原生会话的默认昵称正确，真实浏览器同房双向画线同步；与正式学生参与区分。
- 封禁测试成员后实际绘画连接断开，33,303 ms 内观察到服务器用户数下降；测试成员已恢复。
- 临时分区权限事务覆盖本社团、其他社团、非成员、管理员；事务回滚后正常成员访问恢复。
- 一个浏览器与七个协议客户端同房共 8 人，保持 10 秒，第九个加入被拒绝。此为短工况，不代表长期稳定或 8 名真人验收。
- 网关／清单／发布准备 10 项 Node 检查通过，运行观测 2 项 Python 检查通过。源码构建后再跑启动器信任边界／Unicode 检查，以及 9 项网关／清单／准备检查均通过。正式 TLS/WSS 绘画已通过，实际文件保存仍待完成。

截图位于本项目 `outputs/drawpile-20261013/`。Qt 原生库会把部分普通运行消息写到 `console.error`；验收需区分这些原生日志、主动撤权断连及真正的脚本异常、CSP 或资源故障。

## NAS 回退材料

目录为 `/vol4/1000/backup/blackroom/game-releases/drawpile-20261013/before`，包含原 dpserver 配置、平台源码与私有配置、原 Drawpile／Nginx 镜像、SQLite 在线备份及字节数／SHA-256 索引。另已完成变更前原生论坛备份，包含上传文件，45,660,905 字节；独立副本 SHA-256 为 `8e4ef1633ec5864f12a2a5b0a095f7f29c223588593cf8d579fde39ce63a9c5f`。归档已回读可打开，SQLite `integrity_check=ok`；尚未做本次完整恢复演练。

正常回退关闭茶绘路由和对应网关，定向撤下清单中的 `drawpile` 条目，保留说明话题、成员回复、作品、卷和其他游戏配置。客户端或网关故障只替换该组件；不覆盖论坛数据库，不将旧匿名端口作为默认恢复方式。切换前再次确认活跃会话为 0。原目录已安装 `docker-compose.override.yaml`，固定现有 server 仓库 digest、取消两处端口并隔离服务器网络；旧目录 Nginx 改用发布目录的 `legacy-nginx.conf`，不再代理绘画 WS，避免无效 DNS 依赖。回退不得直接撤掉此 override 重新打开匿名入口。

## 正式部署与验收

| 组件 | 已部署 image ID |
| --- | --- |
| 客户端 `blackroom-drawpile-web` | `sha256:2e61f94f31dc714783db3804f9ba49e6c476949a037f22973daf2ad3add35c4d` |
| 网关 `blackroom-games-gateway-drawpile` | `sha256:4e0da07ff5184cf8bc3f2efe9fbad8337a1ea133c30d2f2d19008b77d4eb0725` |
| 服务端 `dpserver-drawpile-srv-1` | `sha256:23cf54b65407fb2b88befccdb9645a63d027fbe13c3bea88146f0a758898308d` |

服务端仓库固定为 `drawpile/drawpile-srv@sha256:ee3311b70571c7777a6c8c9b4789397babb4f45f46ba0bcf1441edc2c959aa4e`，与旧容器实际 image ID 一致。发布文件 `compose.yaml` 指定已测 image ID，项目名 `blackroom-drawpile`。客户端和网关只读、降权、cap_drop ALL，预算如上；原服务卷保留。

Pangolin 新路由 ID `measly-anniella-pulchra`，HTTPS `drawpile.muwei.xyz` → NAS Site `http://172.16.243.5:8080`。用户当下确认关闭仅该新路由的额外 Pangolin 组织 SSO，认证由 BlackRoom 成员网关负责；Pangolin 显示“未受到保护”只表示自身 SSO 不启用，成员门禁仍覆盖页面、资源、资料和 WS。现有其他路由未调整，DNS 沿用已存在通配记录。

新增说明话题 [175](https://discourse.muwei.xyz/t/topic/175)，原生 `discobot`（ID -2）发布。论坛配置保留原游戏条目后追加 `drawpile`，未替换现有网关私有文件；主题组件仍为 6，增加独立 SVG 封面。论坛、既有两款游戏及其网关容器 ID 均保持不变，没有重启。

正式 Chrome 从目录一次点击打开新标签页，默认昵称进入实际名单；复制本站 HTTPS 邀请并打开第二客户端、手改中文／emoji 昵称、WSS 双向画线和中文聊天均已观察。正式两个客户端属于同一真实管理员账号，不等于两名真实学生参与；隔离测试的 A/B 是两个独立原生身份。密码会话在最终隔离制品完成缺失密码提示、手动密码、含密码邀请自动加入，房间彼此独立。短容量复测为两个原生浏览器与六个协议客户端共 8 人、10 秒，第九个拒绝。

公网匿名 WASM、启动器、资料及 WS 均返回 401；Mac 到原 3003/27750 无法连接，NAS IPv6 loopback 原端口和 27751/27780 也未开放；Docker 服务器无发布端口且只连接 internal backend。正式镜像与隔离镜像一致，相关容器检查无 OOM／重启。NAS 原有五分钟观测已增加茶绘网关、客户端、服务器和匿名边界目标，人工运行返回 OK；未创建 Codex 定时任务。

实际文件保存待完成：原生客户端已生成作品并进入 Save 确认；Qt 6.7 在支持的浏览器调用系统文件选择器，不触发普通下载事件。桌面 CUA 报 Mac 锁屏，已请求用户手动解锁。未取得本地文件前不认定保存通过，不发布公告。稳定指南 160 的修订与更新公告草案在 `outputs/blackroom-updates/drawpile-20261013`，当前 `online_verified=false`。

本次未验证 Safari／手机触摸、两名真实学生参与、完整恢复演练或长期容量。当前运行观测只代表已采样状态，不代表 24 小时观察已结束。
