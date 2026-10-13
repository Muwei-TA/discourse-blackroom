# 播客板块

2026-10-11 创建成员共享的 [播客板块](https://blackroom.qzz.io/c/podcasts/49)，类别 ID `49`、slug `podcasts`。侧栏社区入口位于图文广场之后。每期节目对应一个话题，成员上传音频、填写简介与主创，听众在话题下回复讨论。

## 配置与使用

- `trust_level_0: full`、`staff: full`：所有具有正常发帖权限的注册成员可浏览、创建话题和回复，包含未加入社团的成员；游客不能浏览板块。正常审核、禁言和发帖频率限制继续适用。
- 保留原来的图片上传白名单，增加 `mp3|m4a|ogg|opus|wav`。上传白名单和大小限制都是全站设置，因此其他允许发帖的板块也可使用音频。
- `max_attachment_size_kb: 65536`，单个附件最多 64 MiB；推荐 MP3。图片大小限制未修改。浏览器对音频编码的兼容性不同，允许后缀不代表每一种编码都能播放。
- 运行 Nginx `client_max_body_size: 65m`，为 64 MiB 文件预留 multipart 开销。launcher 的 `containers/app.yml` 中持久化 `params.upload_size: 65m`。已执行 `nginx -t` 与平滑 reload，未重启或重建 Discourse 容器。
- 发帖模板包含收听本期、本期简介、主创与时长、可选时间轴及讨论问题。通过原生编辑器上传后会自动生成音频标记；Markdown 形式为 `![名称|audio](upload://...)`。
- 侧栏使用 `headphones` 耳机图标，该图标须包含在原生 `svg_icon_subset` 设置中。创建脚本同时注册图标并保留已有图标列表；仅保存 SidebarUrl 的图标名称不足以保证图形已加载。
- [欢迎试听](https://blackroom.qzz.io/t/topic/123) 为约 18 秒的系统合成语音，明确标注用途和来源，作为可收听的站内示例保留。

板块的权限由服务端 Guardian 控制，不依赖隐藏入口。站点仍保持 `login_required: true`、`invite_only: true`。`secure_uploads` 仍为 `false`：**持有音频附件完整地址的人可以直接取得文件，即使未登录**。不要把板块页面权限视为附件保密保障。此板块用于成员可共享的节目，不承载私有社团录音或敏感个人信息。

## 维护与回退

创建脚本是 `script/setup_podcasts.rb`，线上副本 `/shared/state/setup_podcasts.rb`。脚本遇到已有同名或同 slug 板块会停止，不重复创建或覆盖成员内容。后续修改使用后台或原生 CategoryUpdater。

变更前记录：

- `/shared/state/podcasts-before-20261010T175208Z.json`：上传设置、注册规则、原分区权限和侧栏排序。
- `/shared/state/podcasts-created-20261010T175208Z.json`：新建对象 ID。
- `/shared/state/nginx-before-podcasts-20261011.conf`：原 Nginx 配置，权限 `0600`。
- `/home/muwei/discourse-docker-preview/containers/app-before-podcasts-20261010T175153Z.yml`：原 launcher 配置，权限 `0600`，包含受保护部署信息，不输出正文。

路径中的 UTC 时间对应北京时间 2026-10-11。回退时只恢复本次修改的上传设置、Nginx 上传上限和 launcher `upload_size` 参数，并经 `nginx -t` 后 reload；不要覆盖后续其他配置。若已有成员节目，降低上限会阻止上传新的大文件，移除后缀会阻止新音频上传。保留已有帖子与附件，不删除板块或恢复整个数据库。暂停发布可将成员权限调为只读，保留管理人员维护能力。

## 验收证据与边界

`script/check_podcasts.rb` 在线上以 `discourse` 用户执行：临时 TL0/TL1 用户分别代表两个社团与未加入社团的成员，检查浏览、创建、回复、自身编辑及不能改板块说明。每个角色实际通过原生 PostCreator 创建话题和回复，结束后数据库回滚，跳过外部任务与 Redis 重复正文记录。游客拒绝访问，管理员保留访问，既有私有社团隔离不变。两个脚本定向 `bin/lint --fix` 通过。

真实登录 Chrome 在 `blackroom.qzz.io` 检查侧栏、类别页面、富文本和 Markdown 发帖模板，发布欢迎试听；MP3 元数据时长 `18.018186`、`readyState: 4`，键盘开始播放后进度从 `0.022724` 推进至 `7.988889`，未出现媒体错误；回复按钮打开编辑器。截图与源音频在 `outputs/podcasts-20261011/`。

原生 UploadCreator 接受 `13,440,078` 字节的 WAV（上传 ID `95`）与欢迎 MP3（上传 ID `94`）；大文件没有发布，属于未引用的验收上传，可由原生孤立上传清理处理。公网未认证 multipart 请求传入 `13,440,410` 字节，返回 `403`，未被旧 10 MB Nginx 限制返回 `413`；这仅证明代理请求大小边界，不代表认证上传完成。

首次验收时，Chrome 扩展缺少 file URLs 权限导致自动选择本地文件失败，原生窗口控制也不可用。用户随后开启权限，2026-10-11 已补齐真实浏览器本地选文件上传验收：在 `discourse.muwei.xyz` 的新建话题编辑器点击上传，分别选择 `13,440,078` 字节 WAV 与 `289,689` 字节 MP3；上传结束后自动生成原生音频标记与播放器。WAV 时长 70 秒，播放进度推进至 `24.652796`；MP3 时长 `18.018186` 秒，播放进度推进至 `6.579065`。两者均为 `readyState: 4`，无媒体错误，未捕获 console error。证据为 `outputs/podcasts-20261011/browser-upload-preview.jpg` 和 `browser-upload-proof.json`。验收草稿已通过编辑器舍弃，没有额外发布测试节目，既有欢迎试听保留。

浏览器操作使用现有管理员登录会话，普通成员权限与发帖、回复仍以此前回滚事务验收为准。没有使用真实学生账户或手机真机验收。初始板块配置没有提供跨页连续播放；后续播放器见下方 UI 更新记录。站内录音、RSS 播客分发与外部平台同步仍未配置。

## 公告与教程

已通过更新助手发布 [使用指南](https://discourse.muwei.xyz/t/topic/127) 和 [上线公告](https://discourse.muwei.xyz/t/topic/128)，分别带“使用指南”“功能更新”标签。公告全站置顶截止北京时间 2026-10-18 02:03:13。真实浏览器从 `blackroom.qzz.io` 公告链接跳转到 `discourse.muwei.xyz` 教程成功，作者、正文、互链、置顶与入口均可见，未捕获 console error。发布回读和截图保存在 `outputs/blackroom-updates/podcasts-20261011/`。

本次修正更新助手将全体 TL0 成员可读类别误当私有社团权限的判断，未改变 bot 权限；新增负向检查证明临时加入私有社团仍会阻止发布。配套发布器与检查脚本定向 lint 通过，生产回滚事务检查通过。详细发布契约与副本见 [更新助手说明](blackroom-updates-bot.md)。

## 侧栏图标修复 — 2026-10-11

创建入口时保存了 `headphones`，但图标没有被纳入站点实际 SVG sprite，导致页面有 `<use href="#headphones">` 引用而缺少对应 symbol，呈现空白。将 `headphones` 加入 `svg_icon_subset` 后，刷新真实登录首页确认对应 symbol 及路径已加载，侧栏显示 16×16 的耳机图标，无 console error。创建脚本已同步且定向 `bin/lint --fix` 通过。

变更前设置为 `svg_icon_subset: ""`，快照为 `/shared/state/podcast-icon-before-20261010T182606Z.json`。回退时仅从列表移除 `headphones`，保留后续添加的其他图标；刷新页面后生效。证据在 `outputs/podcasts-20261011/icon-fix/homepage.jpg` 与 `sidebar.jpg`。本次为外观遗漏修复，未改变发帖、音频上传、权限或运行容器，不重复发布功能公告。

## 播客频道 UI — 2026-10-11

用户评审机核风格原型后，安装独立主题组件 **BlackRoom Podcasts**，ID `5`，关联现有 Foundation `-1` 与 Horizon `-2`。无核心源码、数据库结构、上传上限、成员权限或运行容器修改；没有重启服务。

### 页面与操作

- 频道使用封面卡片与最新一期入口。只展示真实话题，类别说明通过「发布说明」单独访问；不导入原型的示例节目。
- 卡片封面来自原生 `topic.image_url`；没有图片时用标题生成文字封面。正式标题和正文没有被改写。首帖正文中的首张正常图片可作为节目封面，详情还支持从首帖读取图片。
- 详情展示封面、主创、收听与收藏入口，保留原帖、编辑、举报和回复操作。桌面正文与本期讨论分列，手机按上下顺序排列。
- 「收听本期」使用底部播放器，支持暂停、进度调整、后退 5 秒与 1×/1.25×/1.5×/2× 倍速。当前页面实例内的站内跳转继续播放；刷新、关闭标签页和跨浏览器不保留进度。原生播放器开始播放时关闭底部播放器，避免重叠。
- 作者在时间轴/章节标题下写有效 `MM:SS` 或 `HH:MM:SS` 行或列表后显示章节跳转；没有章节时不生成内容。
- 「收藏」使用账号原生书签，「我的收藏」进入本类别原生书签列表。输入框「筛选已加载节目」只筛选当前加载的标题；「搜索全部节目」进入限定播客类别的原生搜索。
- 新建节目继续使用原生「新建话题」，上传、分类模板、草稿、审核与发帖限制沿用既有逻辑。

### 源码、归档与回退

本机源码为 `themes/blackroom-podcasts/`；线上持久副本在 `/shared/state/podcast-ui-20261011/source/`，安装脚本 `/shared/state/podcast-ui-20261011/install.rb` 对应本机 `script/install_podcast_ui.rb`。父主题原关联记录在 `/shared/state/podcast-ui-20261011/parents-before.json`，权限 `0600`。源文件、安装脚本和关联快照归档到 NAS `/vol4/1000/backup/blackroom/theme-releases/podcast-ui-20261011/`，没有在 Mac 创建生产备份。

最终归档 `source-and-install-final-v2.tar.gz` 的 SHA256 为 `0ba1905e03ae68d577a9c759029a065052e5829dca65b46ebea129827e7f28b6`，tar 目录可读。线上与本地 SCSS SHA256 均为 `be6b91e73d8821307bbdb7eb2a9af7f65af8e41878cbf9a2409adbcdaec52dc2`。安装脚本使用原生 `Theme.notify_theme_change` 同步父主题样式缓存；仅清理 Theme 对象缓存不足以确认现有页面已收到最终 CSS。

关闭本次 UI：

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner /shared/state/podcast-ui-20261011/install.rb --disable'
```

该操作只解除本组件关联，保留其他组件和所有节目、附件、回复及书签；刷新页面后回到原生布局。重新启用使用 `--enable`。安装脚本不带参数仅导入/更新，已关联组件的更新会生效；初次未关联时可用 `?preview_theme_id=5` 独立预览。

### 验证与边界

独立预览先定位并修正主题服务注册兼容问题，正式启用前没有关联父主题。主题字段编译无错误，源码定向 ESLint、Prettier、Stylelint、RuboCop、Syntax Tree 检查通过。浏览器解析检查覆盖安全 URL、原生 audio/source、emoji 排除、换行/列表时间轴、非法时间与章节边界。

真实登录 Chrome 在正式页面验证欢迎音频播放、列表→详情连续播放、暂停、键盘进度跳转、原生播放器互斥、节目筛选、原生书签保存与播客收藏列表、回复和新建话题编辑器。测试无提醒书签已移除，空回复与节目模板已舍弃，没有发布测试节目或回复。桌面、390px 手机宽度与 Horizon 页面已检查；普通列表保持原生布局。证据在 `outputs/podcast-ui-20261011/`。

没有使用真实学生账号或手机真机重新验收；未重复大文件上传或修改既有上传配置。欢迎试听没有作者时间轴，章节解析使用独立测试样本验证，不声称完成长节目章节与大量评论的实播验收。

本次更新助手公告为 [播客频道与收听体验](https://discourse.muwei.xyz/t/topic/134)，带“功能更新”标签；已有 [播客教程](https://discourse.muwei.xyz/t/topic/127) 已原址修订并保留“使用指南”标签与成员回复。公告全站置顶截至北京时间 2026-10-18 15:42:18，真实浏览器已回读作者、正文、双向链接与置顶图标。发布清单和证据在 `outputs/blackroom-updates/podcast-ui-20261011/`。
