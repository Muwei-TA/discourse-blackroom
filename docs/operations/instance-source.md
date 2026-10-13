# BlackRoom 实例源码

本仓库保存 2026-10-13 从运行实例收集的 Discourse 源码及维护配套文件。仓库公开，不保存生产凭据或业务数据。

## 来源与版本

- Discourse core：`6318da11adede54e9e5b2bbbeef8a79c2157503c`，与运行容器 `app` 的 `/var/www/discourse` HEAD 一致。已收集该目录的 tracked 修改；其余 core 文件沿用该提交。
- 运行中的附加插件：`discourse-resend`、`discourse-doc-categories`、`discourse-blackroom-moderation`、`blackroom-mcp-images`、`blackroom-games`、`blackroom-mcp-games`、`docker_manager`。持久化软链接已展开为源码，未带入嵌套 `.git` 或 AppleDouble 文件。
- 官方附加插件版本：`discourse-doc-categories` 为 `ad921bb9e2767975bc725ce7ffa8b51d0bbe9938`；`docker_manager` 为 `0d26ddaac1f5073d989f689c6b928cbb53d93c0d`。许可证随源码保留。
- 从数据库通过原生 `ThemeStore::ZipExporter` 导出 8 个当前主题：Foundation、Horizon、BlackRoom Avatar Crop、BlackRoom Knowledge Base、Topic List Thumbnails、BlackRoom Image Annotator、BlackRoom Podcasts、BlackRoom Games。导出包含主题字段和主题专用资产，主题目录也保留本地测试与维护源码。主题数据库关联和实际设置值不属于这个源码导出。
- 游戏成员网关及发布检查：来自 NAS 当前平台 `source` 目录，位于 `services/blackroom-games-gateway/` 和 `script/games-release/`。清单与 Compose 仅提供原有示例。
- 机器人当前脚本来自运行实例的 `/shared/state/`；备份检查、栏目入口和翻译脚本来自 NAS 持久部署目录。其余配置与检查脚本、运维文档来自维护工作区。

[源码校验清单](instance-source-manifest.json) 记录 649 个运行实例/原生主题导出文件的 SHA-256，用于核对源码，不代表完整部署配置或数据库备份。清单之外的文档、测试、示例与维护脚本作为配套文件收录。

## 内容边界与部署

生产 `containers/app.yml`、私有网关配置、API key、密码、OAuth token、数据库、Redis、上传附件、备份、日志、配置快照、成员与帖子数据、浏览器截图及本地输出均不提交。其他独立游戏程序不放入 Discourse 仓库；此处只包含论坛接入和网关。

本仓库是源码交付，不是整站恢复备份，也不会自动将配置应用到生产。不要批量执行 `script/` 中的配置或维护脚本：它们可能写入站点设置、分区或帖子，需要先确认目标环境及具体动作。

部署前按 [部署说明](deployment.md) 和对应功能手册准备受保护配置、插件持久化、主题导入/启用与权限。备份及恢复流程见 [恢复手册](resilience.md)。文档中的本机证据路径与归档路径仅是维护记录，相关制品未发布到本仓库。

## 此次源码交付验证

- 649 个文件与导出制品的 SHA-256 完全一致；Ruby、shell、Python、JSON 的 133 项语法检查通过。
- 游戏网关与发布准备的 15 项 Node 测试通过；备份检查 1 项与运行观测 2 项 Python 测试通过。使用维护工作区已有依赖，依赖目录不提交。
- Gitleaks 8.30.1 对新增提交内容扫描未发现凭据泄漏。差异空白检查通过，原样保留的第三方 `markerjs2.js` 有两处既有尾随空白。
- 此次没有变更或重启生产服务，没有触发邮件或发帖，没有执行整站重建、数据库恢复或真实成员端到端测试。
