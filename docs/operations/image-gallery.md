# 图文广场

2026-10-08 已在运行中的 `app` 容器配置，入口为 [图文广场](https://discourse.muwei.xyz/c/image-gallery/47)。

## 配置契约

- 独立分区：`47`，名称“图文广场”，slug 为 `image-gallery`，与“资源共享”一样使用共享分区权限。登录成员可以发布与回复，不改变站点登录或公网入口规则。
- 侧边栏：Community 的“知识库”之后新增“图文广场”；SidebarUrl ID 为 `35`。
- 官方主题组件：`Topic List Thumbnails`，Theme ID 为 `3`，接入 Foundation (`-1`) 与 Horizon (`-2`)。
- 来源：<https://github.com/discourse/discourse-topic-thumbnails>，安装 commit 为 `a104bf91dd105bb0491558a5a9d6755f38dfadd9`。
- 设置：`default_thumbnail_mode=none`、`masonry_categories=47`、`mobile_thumbnails=true`。其他分区保持原展示模式。
- 系统说明话题：`68`，“关于图文广场”。初始没有作品图片，说明话题显示占位封面。

维护入口：[组件管理](https://discourse.muwei.xyz/admin/customize/themes/3)。发布作品时在“图文广场”新建话题，首帖放图片与说明；默认以首张图片为封面，可在图片 Markdown 中添加 `|thumbnail` 指定封面。私有社团内容继续保留在原有私有分区。

## 验证与边界

- Chrome 已验证实际侧边栏入口、分区页面与 `topic-thumbnails-masonry` 样式加载；Foundation 与 Horizon 页面均可打开。Horizon 保留原生卡片结构，其卡片文字位置与 Foundation 不同。
- 390×844 窄屏下启用瀑布流且无横向溢出；不是手机真机验收。
- 管理员、动画社成员、文学社成员及无社团成员的服务端读写检查通过；临时身份使用事务回滚。原有两个社团与绘画打卡的隔离权限仍通过。
- 初始没有真实作品，尚未验证多张不同尺寸图片的上传、缩略图生成及多列排列；不得把说明卡片验证称为真实图片业务闭环。
- 页面检查期间未捕获到 console error。
- 本机 `bin/lint --fix` 受系统 Ruby 缺少 `Array#filter_map` 限制，未执行成功；Ruby 语法检查与线上断言已通过。

相关脚本为 [首次配置](../../script/setup_image_gallery.rb) 与 [权限/设置检查](../../script/check_image_gallery.rb)。首次配置脚本遇到已存在分区会停止，不能重复运行。检查脚本可用 `docker --context nas exec -u discourse app` 在实际源码环境中执行。

## 缓存与回退

分类缓存按语言保存。Rails runner 创建分区时使用 `I18n.locale = SiteSetting.default_locale`，变更后在相同 locale 下执行 `Site.clear_cache`。本次初次创建时中文缓存仍含旧列表，导致客户端 404；刷新中文缓存后恢复。

NAS 容器内保留：

- `/shared/state/image-gallery-before-20261008T143536Z.json`：原分类 ID、权限、主题子组件关系与侧边栏位置。
- `/shared/state/image-gallery-created-20261008T143536Z.json`：新增对象 ID 和安装版本。

只恢复列表展示时，将组件 `masonry_categories` 清空，保留分区、话题与上传文件。完全停用组件时，在两个父主题中移除 Theme `3` 的关联；不删除业务内容。侧边栏入口可独立移除或恢复。后续有成员作品时不得删除分区作为回退手段。

本次不需要重建或重启容器。
