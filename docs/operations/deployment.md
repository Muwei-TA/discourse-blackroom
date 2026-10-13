# BlackRoom 部署与工具说明

以下部署位置在 2026-10-10 重新核对；较早的操作记录保留日期。执行维护前按任务复核，避免把历史记录当成运行状态。

## 位置与职责

| 对象 | 位置 | 用途 |
| --- | --- | --- |
| 线上站点 | `https://discourse.muwei.xyz` | 实际用户访问 |
| 管理后台 | `https://discourse.muwei.xyz/admin` | 设置、群组、审核、主题与备份 |
| 本机源码 | `/Users/muwei/Documents/Codex/discourse` | 源码参考、维护文档和必要代码修改 |
| NAS SSH | `nas` | 已配置的 SSH 别名 |
| 本机 Docker context | `nas`，端点 `ssh://muwei@nas` | 操作 NAS 上的 Docker |
| 部署目录 | `/home/muwei/discourse-docker-preview` | launcher、部署配置和自定义插件 |
| 部署配置 | `containers/app.yml`（相对部署目录） | 包含凭据，现场权限为 `0600` |
| 活跃容器 | `app` | Discourse、数据库与配套进程 |
| 容器源码 | `/var/www/discourse` | 实际运行版本 |
| 持久数据 | `/vol1/docker/discourse-preview/shared` → `/shared` | 数据库、上传文件、备份、配置快照 |
| 备份归档卷 | `/vol4/1000/backup/blackroom` | 每日站点备份副本、版本镜像与恢复材料 |
| 内网源站 | `192.168.50.28:18180` | 内网诊断；不能替代公网浏览器验收 |

目录名称保留了 `preview`，但该部署承载线上站点。不要把它当成可随意清理的临时环境。

## 最小现场检查

在本机使用明确的 Docker context：

```sh
docker context ls
docker --context nas ps --filter name=app --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

只输出必要字段，不运行会展示完整凭据的 `docker inspect` 或 `printenv`。需要 Rails 检查时使用 `discourse` 用户：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner "puts({base_url: Discourse.base_url, notification_email: SiteSetting.notification_email, delivery: ActionMailer::Base.delivery_method}.to_json)"'
```

默认 root 用户直接启动 Rails runner 曾导致数据库配置与 Git 所有权错误。不要通过创建新数据库或放宽全局权限处理这个执行用户问题。

公网入口可能要求 Pangolin 登录。未登录的 HTTP 请求跳转到身份验证页面，不等于 Discourse 故障；使用已登录的浏览器核验页面。

## 页脚技术支持提示

2026-10-10 将线上原生设置 `enable_powered_by_discourse` 从 `true` 改为 `false`，关闭网页页脚“由 Discourse 提供技术支持”链接。使用 `SiteSetting` 写入，无需修改核心源码或重建容器。已登录 Chrome 刷新首页后，提示文字及对应链接均不存在，页面底部截图在 `outputs/powered-by-20261010/homepage-footer.png`，未捕获 console error。

需要恢复时在管理后台搜索 `enable_powered_by_discourse` 并启用，或以 `discourse` 用户执行 Rails runner 将 `SiteSetting.enable_powered_by_discourse` 设为 `true`，再刷新页面核验。本次属于外观设置维护，没有新增功能或成员操作步骤，不触发更新助手的功能公告与教程发布。

## 编辑器图片标注

编辑器图片标注于 2026-10-11 通过独立主题组件接入，覆盖富文本和 Markdown，无需重建或重启容器。源码、操作步骤、双域名图片处理和回退方法见 [图片标注说明](image-annotator.md)。

## 播客上传

2026-10-11 配置播客成员板块，全站附件上限为 64 MiB，运行 Nginx 上传请求上限与 launcher `params.upload_size` 均为 `65m`，为 multipart 预留开销。采用 Nginx 平滑 reload，未重建容器；配置、权限、回退与验收边界见 [播客板块](podcasts.md)。

## AI 标签推荐

2026-10-11 启用官方 AI Helper 标签推荐，普通登录成员在写完正文后可从标签下拉框点击“显示 AI 建议”，自行采纳已有标签。使用 NAS 本地 CPU BGE-M3，未改写帖子标签；配置、成员权限验收、推荐质量限制和回退方法见 [AI 标签推荐](ai-tag-suggestions.md)。

2026-10-11 用户确认原型后，启用独立 `BlackRoom Podcasts` 主题组件（ID `5`），提供节目卡片、详情与底部播放器；源码、NAS 归档、停用命令及验收边界同见 [播客板块](podcasts.md#播客频道-ui--2026-10-11)。未重启容器。

## 原生 MCP

2026-10-13 按授权增加游戏目录查询和管理员接入准备两工具，持久化插件与重建恢复 hook，平滑重载 Web。全站 38 工具；ChatGPT 管理目录 38 项、discobot 目录 18 项。真实 HTTP 调用通过，准备工具不落地部署，既有游戏配置与容器未变。权限、回退与证据见 [游戏 MCP 管理](games-mcp.md)。

帖子图片读取扩展于 2026-10-11 按用户授权加载并启用；只重启 Web 进程，原工具开关及 OAuth scope 保留。全站启用工具为 36 个，两个 ChatGPT 连接目录均已包含新工具，真实 HTTP 已返回图片本体；接口、验收边界与回退说明见 [MCP 图片读取](mcp-images.md)。

2026-10-11 按用户授权将原生 `mcp_server_enabled` 从 `false` 改为 `true`，无需重启或重建容器。已核查数据库持久化值与已登录 Chrome 的 MCP 概述页面，状态为“可用”。端点为 `https://discourse.muwei.xyz/mcp`，管理入口为 `/admin/config/mcp`。

公网与内网源站的 `/.well-known/oauth-protected-resource/mcp` 均返回 HTTP 200；未携带授权的 MCP `initialize` POST 返回 HTTP 401、`Authorization required` 和 Bearer 认证挑战。此结果验证服务启用与认证边界，不代表已完成客户端 OAuth 或实际工具调用。

本次未更改能力、群组访问规则或客户端授权。验收时暴露的工具、资源、提示均为 0，已注册客户端和用户授权均为 0；实际使用仍需选择所需能力并配置、批准目标客户端，再由用户完成 OAuth。当前只是管理员服务启用，尚未向成员开放可用功能，因此未触发更新助手的功能公告与教程发布。

变更前快照为 NAS 容器内 `/shared/state/mcp-before-20261011-082221.json`。需要关闭时通过原生管理设置将 `mcp_server_enabled` 设为 `false`，或使用部署说明中的 `discourse` 用户执行 Rails runner；无需恢复数据库。后台证据为 `outputs/mcp-enable-20261011/admin-overview.png`。

同日后续按用户选择完成 ChatGPT 管理范围的 35 个工具和管理员群组访问规则，已核验并注册官方 CIMD 客户端。首次创建出现环境权限错误，用户手动继续后已完成真实 OAuth：ChatGPT 显示已连接，站点回读 1 条活跃授权、1 个有效 token；当前状态、权限边界与恢复记录见 [ChatGPT MCP 接入](mcp-chatgpt.md)。

## 邮件

- 使用已安装的 Resend CLI 管理域名、受限发信凭据和投递记录。本机已使用 `/Users/muwei/.resend/bin/resend`；先确认当前可执行文件与认证状态。
- 认证状态检查须过滤凭据字段；不要直接把 `whoami` 的完整输出写进日志。
- 域名 `muwei.xyz` 已验证，通知发件地址为 `noreply@muwei.xyz`。操作前重新核查当前域名与站点设置。
- SMTP 连接曾在 NAS 和本机被关闭；实际发送方式是 Resend HTTPS API。后台 SMTP 配置中 `smtp_address` 和 `smtp_password` 同时用于选择适配器和提供凭据。
- 源码及接入说明在 [Resend 插件 README](../../plugins/discourse-resend/README.md)。该目录被上游忽略规则排除，不能仅凭 Git 状态判断插件是否已保存或能从仓库恢复。
- NAS 插件源位于 `/home/muwei/discourse-docker-preview/plugins/discourse-resend`，部署 YAML 已配置映射到 `/var/www/discourse/plugins/discourse-resend`。2026-10-10 实际容器只有 shared 与日志挂载，Resend 和知识库插件仍位于容器文件系统；本次已保存运行镜像和插件源码。重建前核对实际挂载和内容，不能把 YAML 中的映射当作当前容器已挂载。
- launcher 使用 shell tracing，启动输出可能包含密钥。捕获并过滤启动输出，或保存到受保护的位置；不要在聊天展示完整命令输出。
- Resend 邮件列表的主题可能含验证码；检查投递状态时隐藏验证码。`delivered` 表示收件服务接受，还须核对实际收件箱和用户操作。

## 检查、快照与恢复

社团设置、分区和权限的记录见 [社团配置记录](blackroom-student-clubs.md)。

权限检查脚本使用事务内临时数据，结束后回滚：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner script/check_club_isolation.rb'
```

脚本属于本项目的维护附加文件；在新建容器或恢复部署后，先确认脚本已同步，再运行。它验证服务端权限，不代表真实成员已登录并完成发帖。

邮件适配器的独立检查：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bundle exec ruby plugins/discourse-resend/test_delivery.rb'
```

配置快照保存在 `/shared/state/`。按本次目标选择对应快照，不批量恢复目录里的所有文件。邮件切换的回滚材料和步骤还保存在 NAS 部署目录的 `RESEND.md`；停止的旧容器 `app-before-resend-20261007` 是本次邮件切换的回退材料，不自动清理。

不要让两个 Discourse 容器同时使用这份数据库卷。重建和升级前确认镜像、运行配置、持久卷、插件、备份和启动方式，准备可执行的回退措施。

2026-10-10 已落实每日原生备份、保留 14 份、包含上传文件，并将归档副本及当前程序恢复集合存到用户指定的 `/vol4/1000/backup/blackroom`。原生备份仍在 `/shared/backups/default` 生成，NAS 每小时第 10 分钟复制新制品到 `/vol4` 并核验；不在 Mac 保存备份。两个路径位于不同存储卷，但同一 NAS 不能覆盖整机或同地点灾害。恢复集合、已通过的隔离演练、定时检查和每次更新流程见 [备份、恢复与更新手册](resilience.md)。

## 开发工具与验证边界

本机系统 Ruby 2.6.10 曾因缺少 `Array#filter_map` 无法运行 `bin/lint`。2026-10-09 已安装 Homebrew Ruby 3.4.11、Node 24.21.0，以及用户目录 `~/.local` 下的 pnpm 10.34.5；`~/.zshenv`、`~/.zprofile` 和 `~/.zshrc` 将这些工具路径置于 PATH 前部，覆盖非交互、登录和交互 zsh（登录时 macOS 的 `path_helper` 会重排 PATH）。Homebrew 默认 Node 链接已切至 Node 24；系统 Ruby 保留，新 shell 默认使用上述版本；已有终端可运行 `source ~/.zshenv` 后重新核对。项目要求以 `Gemfile`、`package.json` 和锁文件为准，升级源码后重新检查。

本地依赖安装与定向 lint：

```sh
ruby -v
node -v
pnpm --version
BUNDLE_FROZEN=true bundle install --jobs 4
pnpm install --frozen-lockfile
bin/lint bin/lint
```

Bundler 使用 `Gemfile.lock` 指定的 4.0.11；依赖安装保持锁文件冻结。不要使用 `sudo gem install` 修改系统 Ruby，也不要为兼容旧 Ruby 改写 lint。生产 bundle 排除了 `stree` 和 `rubocop`，不在生产环境为本地检查安装开发工具。已通过 `bin/lint` 对 `app/models/bookmark.rb`、`frontend/discourse/app/lib/avatar-utils.js`、`app/assets/stylesheets/common/base/bbcode.scss` 和 `.github/workflows/linting.yml` 的定向检查，覆盖 RuboCop、Syntax Tree、ESLint、Prettier、Stylelint 和 YAML 语法检查。定向 lint 通过不代表全库 lint 或站点业务验收通过。

Node 切换时保留了原 npm 目录 `/opt/homebrew/lib/node_modules/npm-before-node24-20261009`，避免覆盖原有文件。Homebrew 依赖升级后旧 Node 25 安装不再作为可直接运行的回退；若需其他版本，先安装或重建并复核，不能仅重新链接旧版本。

仅涉及 Agent 文档时检查入口、链接、事实来源和差异即可；涉及代码再运行对应语法、单元或浏览器检查。备份制品、服务端权限检查、实际页面、真实成员操作分别报告。

## 游戏平台

2026-10-12 晚游戏板块接入正式站点，2026-10-13 完成两款封面、目录一键新标签启动及加载过渡页升级。入口为 `/c/games/53`，独立主题组件 ID 6；弹球与绘画通过各自成员网关访问 `bonk.muwei.xyz`、`skribbl.muwei.xyz`，游戏程序仍独立运行于 Docker，接入契约兼容的游戏更新无需发布论坛代码。原匿名 3001/3002 已撤除；本次 UI 升级只平滑重载论坛 Web，未重启游戏容器。

生产位置、权限、独立更新、NAS 原生观测、回退与验收边界见 [游戏平台运维](games.md)。稳定指南为话题 160，本次升级公告为 171，已完成浏览器回读。上线前后备份及源码/镜像归档位于 NAS `/vol4/1000/backup/blackroom/game-releases/games-20261012`；归档可读不等于新完整数据库恢复演练，首个 24 小时观察尚未完成。

同日后续已完成默认站点用户名接入：平台提供受成员门禁保护的同源 `/_blackroom/me`，两款独立游戏填入昵称并保留手动修改；实际首页和房间名单已完成测试环境及正式 Chrome 验收。指南 160 已修订，公告 172 已发布/回读；该次变更前后源码、配置、游戏/网关镜像及发布后论坛备份在 NAS `game-releases/games-username-20261013`。当前镜像、Unicode 限制、旧昵称缓存处理和定向回退说明同见游戏平台运维文档。


2026-10-13 后续部署茶绘，入口为游戏目录中的第三张卡片及 `drawpile.muwei.xyz`。旧 3003／27750 已撤下，成员网关负责所有游戏路径，论坛和现有游戏未重启。核心绘画已通过正式 Chrome，文件保存验收与公告尚待完成；当前制品、回退及未验收项见 [茶绘接入记录](drawpile.md)。

2026-10-13 将当前 NAS 3003 的 FreeBoardGames 桌游服务接入第四张游戏卡片，正式入口 `boardgames.muwei.xyz`，仅成员网关开放；原匿名 3003 已撤下。目录、默认昵称、邀请、中文改名与井字棋终局已通过正式 Chrome，论坛及原三款游戏未重启，数据库/Redis 与持久卷保留。详见 [黑房桌游接入记录](freeboardgames.md)。
