# Paperclip 团队接管与运行限制

记录日期：2026-10-11。Paperclip 团队接管配置与生产站点操作权限分开。

**当前状态：运行环境修复与团队资料接管已完成。** 四角色普通沙箱真实工具可用；CMP-1/2/3/4 已完成并有各自文件阅读、持久文档和独立审核证据。当前方案为 revision 7，配置回执 revision 3，独立审核 revision 2。下方早期阻塞与候选过程保留作历史证据，不代表当前阻塞。团队仍未获得 NAS/Discourse 直接生产操作权限。

交付入口：

- [当前接管方案](https://paperclip.muweinas.fnos.net:8443/CMP/issues/CMP-1#document-plan)
- [运维资料接管回执](https://paperclip.muweinas.fnos.net:8443/CMP/issues/CMP-2#document-handoff-receipt)
- [开发盘点](https://paperclip.muweinas.fnos.net:8443/CMP/issues/CMP-3#document-findings)
- [独立审核](https://paperclip.muweinas.fnos.net:8443/CMP/issues/CMP-4#document-audit)


## 交接位置

Paperclip 任务：`https://paperclip.muweinas.fnos.net:8443/CMP/issues/CMP-1`。
现有任务 CMP-2（运维）、CMP-3（开发）、CMP-4（审核）继续使用，不重复创建团队。

项目工作区：`/paperclip/instances/default/projects/14aa3e2d-a1f4-4b07-9312-d3d4581d1695/c66f61b0-22cb-463a-9447-6ea084a29c7c/_default`。

该目录的 `blackroom-handoff/HANDOFF.md` 为脱敏交接资料，附带 `docs/operations/deployment.md`、`resilience.md`、`blackroom-updates-bot.md`。Mac 的 SSH 别名、Docker context 与源码路径不能假设在 Paperclip 容器可用。

交接包不包含数据库、备份归档、部署 YAML、邮件凭据或 SSH 私钥。四角色 AGENTS.md 已保存 HANDOFF 引用并保留平台指令，专业角色的招聘和技能创建权限关闭，定时 heartbeat 关闭，最大并发 1。协调默认 Luna，常规开发/运维 Sol，审核 Luna，复杂事故/迁移/跨模块任务级升级 Astra；使用已有订阅，实际价格未知就标未知。

负责人当前已保存默认 gpt-6-luna、单并发、沙箱绕过关闭；为避免 /app 可信目录问题，使用 Codex CLI 与 --cd 指向上述接管工作区。负责人已在容器兼容修复验收后恢复，继续原接管任务。模型连接与保存测试不能替代真实工具执行。执行细节以 Paperclip 当前配置与任务证据为准。

## 已确认的两个环境问题

1. 项目工作区原先没有 Git 元数据，Codex 正常沙箱启动被可信目录检查拒绝。已以 node 用户初始化 Git，未提交或删除已有资料，空分支为 `codex/blackroom-handoff`。随后专业角色连接测试通过。
2. 专业角色真实命令执行仍失败：`bwrap: No permissions to create a new namespace`。Paperclip 容器中 node 用户 `unshare -Ur true` 为 Operation not permitted；同一 NAS 主机上 muwei 执行成功。Docker 28.5.2，容器 `docker-paperclip-1` 没有 privileged、额外 capability 或自定义 security_opt。现有 Docker 默认 syscall 限制是主要嫌疑，需在受控副本验证。

当前 Codex 0.162.1 的 `use_legacy_landlock=true` 不能解决：实际试验报 `filesystem-restricted execution requires bubblewrap to isolate app-server sockets`。未关闭专业角色沙箱，未调整 NAS 全局 sysctl，未增加容器权限。

官方参考：[Docker seccomp 说明](https://docs.docker.com/engine/security/seccomp/)。默认 profile 限制 namespace、mount 等操作；自定义 profile 属于安全边界变更，需具体授权。

## 已批准的 seccomp 兼容修复范围

目标仅 Paperclip 服务 `docker-paperclip-1`，Compose 文件 `/vol1/1000/docker/paperclip/docker/docker-compose.quickstart.yml`。不修改 BlackRoom 的 app 容器、生产卷、网络、Pangolin 或 NAS 全局配置。

批准后先在 NAS 的 Paperclip 部署目录保存受保护配置及当前镜像回退材料，保留 `/vol1/1000/docker/paperclip/data/docker-paperclip` 数据卷。必须复用现有环境注入方式：孤立执行 Compose config 会报 BETTER_AUTH_SECRET 未注入，不应重新生成认证 secret 或打印它。

采用独立容器测试与匹配 Docker 版本的默认 seccomp 基线，逐项允许 Codex 创建其内部沙箱所需 namespace/mount syscall，候选范围限于 clone、unshare、setns、mount、umount2、pivot_root；不启用 privileged，不授予 SYS_ADMIN，不挂 Docker socket，不直接使用 seccomp=unconfined。若该限定范围仍不足，停止并给出新证据，不扩大授权。

验证副本能读取交接包、在指定工作区写临时文件、拒绝工作区外写入后，才应用同一 profile 并短暂重建 Paperclip 服务。该步骤会中断 Paperclip 当时运行的任务，应先停止并保存现有进度。上线后再检查登录、现有任务/文档、四角色真实工具调用与文件阅读回执；失败恢复原启动配置和镜像，保留数据卷，禁止覆盖数据库。

seccomp 限定范围已获用户批准，但运行验收尚未通过，不把团队报告为具备实际维护执行能力。NAS/Discourse 的直接生产接入仍是独立授权事项，首选继续使用脱敏快照或仅输出固定白名单字段的只读通道。


## 2026-10-11 限定副本验证与额外 AppArmor 阻塞

用户明确批准受限 seccomp 副本验证及通过后的 Paperclip 重建。本轮尚未重建运行实例；原容器 ID 仍为 `ca0310b9c1ad15928453d5e18b3e16bdd6a51bcaba535c56b8506e96ff8cd721`，`SecurityOpt=null`、`AppArmorProfile=docker-default`。

NAS 回退和证据目录为 `/vol1/1000/docker/paperclip/ops/sandbox-20261011/`。`rollback/` 内保留 0600 的原 Compose 与环境文件；当前镜像已标记 `docker-paperclip:rollback-sandbox-20261011`。凭据文件未展示或复制到 Mac。测试日志在 `evidence/`，未挂载 Paperclip 数据卷或任何 BlackRoom 数据。

与 Docker 28.5.2 的 vendor.mod 对齐，使用官方 `moby/profiles/seccomp v0.1.0` 默认 JSON，SHA-256 `01536f1d1df938ae611eba20d6349e0de7a99b6ecdee1549427a0b01b8301e28`。候选只追加 clone、unshare、mount、umount2、pivot_root 五个 ALLOW，其他 31 组规则与默认 ERRNO 均不变；未加入 setns 或 clone3，也未启用 unconfined、capability 或 privileged。

| 副本验证 | 结果 |
| --- | --- |
| 仅 clone/unshare，node 用户 `unshare -Ur true` | exit 0，用户命名空间可用 |
| 同一规则运行完整 Codex sandbox | mount propagation 报 Operation not permitted |
| 增加 mount/umount2/pivot_root 后运行 Codex sandbox | mount propagation 仍报 Permission denied；沙箱初始化失败，尚未达到文件读取/写入及越界拒绝测试 |

测试使用同镜像、network none、node 用户和独立工作目录。失败日志与元数据已保留，三个本次测试容器已移除，工作目录和材料保留。

副本仍绑定 docker-default AppArmor。匹配版本的 [官方 AppArmor 模板](https://raw.githubusercontent.com/moby/profiles/apparmor/v0.1.0/apparmor/template.go) 明确包含 `deny mount`，与当前 EACCES 结果一致；未能读取 NAS kernel audit，因为 sudo 需要密码，不能声称已取得 audit DENIED 日志。

为后续评审准备了 `paperclip-codex-sandbox.apparmor.candidate`：独立 profile 名称，基于上述模板保留 proc/sys/ptrace/signal 等限制，只将 deny mount 替换为 mount 与 pivot_root 放行。该规则不是按命令名称限制 mount；Docker 无 SYS_ADMIN 与非 root agent 的用户命名空间是配套边界。候选位于 NAS `ops/sandbox-20261011/`，本机 diff/源文件与测试摘要位于 `outputs/paperclip-handoff-20261011/`。

NAS `/usr/sbin/apparmor_parser -Q -K <candidate>` 编译成功，`-Q` 不加载到内核，`-K` 不写策略缓存。未加载或应用候选，未修改全局 AppArmor、Docker daemon 或 NAS sysctl。此扩展不在原 seccomp 授权内，已另行请求用户批准；批准后还需管理员加载该独立策略，当前 sudo 非免密，用户自行处理认证，不发送密码。必须继续独立副本的读取、工作区内写入与工作区外拒绝验收，通过后才重建 Paperclip。


## 2026-10-11 AppArmor 授权、部署与真实命令验收

用户另行明确批准 Paperclip 专用 AppArmor profile 范围。已加载 `paperclip-codex-sandbox`，没有修改 `docker-default`、Docker daemon 或 NAS 全局 sysctl。

SSH sudo 非免密；使用现有 Docker 管理通道的一次性策略加载容器执行固定 apparmor_parser 命令。辅助容器 network none、只读根文件系统、cap-drop ALL，仅加 MAC_ADMIN；只把 AppArmor 的 `.load` 入口设为可写，配置、源策略与其余 securityfs 只读，不挂 Docker socket 或业务卷，不使用 SYS_ADMIN/privileged。该辅助容器本身使用 unconfined AppArmor 以执行已批准的策略加载，这不是关闭全局 AppArmor或取消 Paperclip 的策略。加载容器已移除，MAC_ADMIN 未授予 Paperclip。

专用策略 SHA-256 为 `1d9bb88c8e84529cd99e22283690c6b6b033c759e43a26d3d3f342f650076ab5`。已以固定 install 命令将同一文件存到 `/etc/apparmor.d/paperclip-codex-sandbox`，内容 hash 匹配；NAS apparmor.service 为 enabled/active，未重启该服务。实际 NAS 重启后的加载尚未演练。

安装的 Codex 0.162.1 使用 `codex sandbox -P :workspace -C <workspace> -- <command>` 做独立自检；旧版本的 `sandbox linux --full-auto` 语法不适用。先前 mount 阻塞发生在执行子命令前；调整安全策略后才暴露旧语法错误，已改用本机 help 与生成协议里声明的 `:workspace` profile。新的自检脚本 `outputs/paperclip-handoff-20261011/check-sandbox.sh` 已通过：普通 node 进程本来能在 outside 控制目录写入，进入 Codex 沙箱后被只读文件系统拒绝，同时交接资料可读、workspace 文件可写。

Compose 仅新增两项 security_opt：受限 seccomp JSON 和专用 AppArmor 名称。实际 resolved 配置核对原 bind 卷、LAN 3100 端口未改变，privileged/cap_add 未新增。原环境文件复用，不重新生成认证 secret。

Paperclip 已短暂重建：新容器 ID `766f48fe46f95b8d60b14aa58a08a5c3ac13fa902045750b1778d7d2fde149f3`，镜像仍为 `sha256:0f3879112fd231ac94f9a3d812d83280504bbc9c35d4b11d88054ecc97044cab`；唯一挂载仍为原 data → /paperclip。HostConfig.Privileged=false、CapAdd=null；实际 seccomp 32 组规则、ERRNO 默认拒绝，只追加五个已批准 syscall；AppArmorProfile=paperclip-codex-sandbox。

重建后在真实容器，以 node、真实接管 cwd 和普通 Codex workspace profile 再次验证文件读取、workspace 写入、workspace 外原本可写的 /paperclip 位置写入拒绝全部通过。仅创建后移除了本次的控制/测试文件。健康接口 status ok，authenticated/private 模式和 databaseBackup ok；Chrome 已登录会话、CMP-1 历史消息和方案保留。这些结果不代替各模型角色实际读取回执，后者由恢复后的现有 CMP-2/3/4 完成。

脱敏验证文件为 `blackroom-handoff/evidence/sandbox-repair-verified.json`，已交给负责人；现有团队与任务继续使用。BlackRoom app 容器 ID 仍为 `189477fce6366dc98d0e0c34cde4bf64663e6bd4b76d3460cd95154f7d8b00ef`，未改站点、数据、网络、DNS或邮件。团队未获得 NAS 私钥、Docker socket 或直接生产访问。

### 回退与边界

NAS `ops/sandbox-20261011/rollback/` 保留原 Compose、环境文件与受保护原容器日志；原镜像 tag 为 `docker-paperclip:rollback-sandbox-20261011`，当前容器程序层另存 `docker-paperclip:runtime-before-sandbox-20261011`（ID `sha256:730e875de70feb55a71c7ad424d30393f0ef487d2776e61dcb86d4b5f5a0df8d`）。这些程序镜像不包含 mounted /paperclip 数据，不是数据库备份或数据库恢复验收。

本次只改变安全配置，未升级代码或迁移数据。若只回退本次变更，先暂停角色、保留当前日志，将原 Compose 恢复，再使用原镜像与同一 data 卷重建；不要覆盖数据库。日后若已发生版本升级/迁移，先核对 schema 兼容性，不套用本次回退。

部署命令复用 NAS 的环境注入与 project 名：`docker compose -p docker --env-file /vol1/1000/docker/paperclip/.env -f /vol1/1000/docker/paperclip/docker/docker-compose.quickstart.yml up -d --no-build --no-deps --force-recreate paperclip`。不要输出环境文件、完整 config JSON或敏感日志。移除专用 AppArmor 策略前先确认无容器使用，并通过同等受控管理员方式执行指定 profile 的 remove；不能卸载默认策略。


### 团队实际验收与可追溯性交付

四角色分别通过自己的模型工具执行了文件阅读，负责人已汇总。本轮资料任务用任务级 Luna 覆盖，默认开发/运维模型仍是 Sol。角色回执对实际模型与 token 来源有自述局限；不能把默认模型字段或界面累计 token 显示当精确账单。实际价格仍未知，未购买新资源或启用模型定时巡检。

五个共享证据文件的 SHA-256 已现场重新核对，与运维/开发回执一致。运维最初将本地 `blackroom-handoff/CMP-2-资料接管回执.md` 当网页链接，实际 Chrome 返回 Page not found；现已保存为 CMP-2 的 `handoff-receipt` 持久 Paperclip document。API 写入回读后，Chrome 实际打开正文成功；审核员仅针对新链接做了补充复核，audit revision 2 确认可追溯性通过。保留原本地文件、原消息及失败记录。

父任务计划和配置回执已收束到当前结项状态，旧“契约待 Board/运行环境阻塞”已标为历史；没有新建额外任务或重复已通过的资料读取。生产真实用户、邮件、页面业务闭环、完整 RTO和 NAS 重启后的策略加载仍不在本轮实际验收内。
