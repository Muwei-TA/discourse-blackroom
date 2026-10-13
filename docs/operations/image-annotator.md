# 编辑器图片标注

2026-10-11 接入 `BlackRoom Image Annotator`，主题组件 ID `4`，覆盖 Foundation（`-1`）和 Horizon（`-2`）。源码在 `themes/blackroom-image-annotator/`；容器内持久副本为 `/shared/state/image-annotator-20261011/source/`。不修改核心、数据库结构或容器启动配置，无需重启。

## 用户操作

富文本编辑器：粘贴或上传截图，点击选中图片，再点击工具栏铅笔“图片标注”。在弹窗中选择箭头、方框、圆圈、文字、高亮或自由画笔，拖动绘制；右上角勾号保存到编辑器，叉号取消。仍需点击“创建话题”或“保存编辑”才会发布。

Markdown 编辑器：点击右侧预览图片旁的“标注”；也可选中完整图片 Markdown 后点击工具栏“图片标注”，仅有一张图片时工具栏直接打开该图片。多图按 Discourse 的 `data-image-index` 与 `IMAGE_MARKDOWN_REGEX` 精确定位，不按 URL 全局替换。预览隐藏时请先显示预览。

当前入口面向已上传的 PNG、JPEG、WebP 图片；GIF、外链和其他附件不进入标注。绘制结果按原始像素输出静态 PNG，保留原有描述和显示尺寸。标注保存为合成图片，再次打开可追加标注，不能单独移动或删除之前已合成的箭头、方框。想保留可重新开始的原图，请在本机保留原始截图；本站不会覆盖原上传文件，但未被帖子引用的上传仍遵循 Discourse 原生清理规则。

## 接入方式与边界

绘图库复用 [Discourse Image Annotator](https://github.com/discourse/discourse-image-annotator) 的 `assets/markerjs2.js`，SHA256 为 `2a378c6e1dbab68b946e10e55c7a42f3cc486c3df6bd463dabe5c5f7bbc3e9ef`，保留原文件及 marker.js 的署名标识。本站封装使用原生 `registerRichEditorExtension`、`onToolbarCreate` 和 `addComposerImageWrapperButton`，不直接安装上游只支持 Markdown 的旧保存代码。

富文本使用 ProseMirror 的选中节点和 `setNodeMarkup`，保存前再次确认原节点未改变。Markdown 保存前确认仍为同一编辑模型且正文未改变；发生编辑、关闭或图片移除时拒绝旧结果，保留当前内容。上传使用 Discourse 原生 `/uploads.json`、CSRF 与服务端上传校验和权限，无外部图片处理服务。

本站通过 `blackroom.qzz.io` 访问时，图片链接仍使用 canonical host `discourse.muwei.xyz`。对本地 `/uploads/` 文件从当前站点路径读取为浏览器 Blob，避免 Canvas 跨域污染；弹窗关闭后恢复图片显示 URL 并释放 Blob。站点域名、代理、CORS 和私有分区权限不改变。

## 更新与回退

先核对 Docker context `nas`、容器 `app` 和 `Discourse.base_url`。将目录同步到上述持久路径，用原生导入方法更新现有组件，必须指定 `theme_id: 4`，再检查所有 `theme_fields` 的 `ensure_baked!` 与 `error`。

本次导入脚本与关联快照分别在 `/shared/state/image-annotator-20261011/install.rb`、`parents-before.json`。无 `--enable` 参数仅导入，管理员可用 `?preview_theme_id=4` 独立预览；验证后加 `--enable` 关联父主题。

回退仅移除父主题中的组件 ID `4`，保留其他组件、源码及上传文件：

```ruby
Theme.where(component: false).each do |parent|
  parent.child_theme_ids = parent.child_theme_ids - [4]
  parent.save!
end
Theme.clear_cache!
```

富文本扩展 API 属于上游实验性接口，升级 Discourse 后复测选中图片、保存、取消和多图替换。

## 验收

- `node themes/blackroom-image-annotator/check.mjs` 检查选中节点、上传边界、保留描述、重复图片精确定位及旧结果拒绝。
- 对本站新代码运行定向 `bin/lint --fix`：ESLint、Prettier、Stylelint 通过；主题编译无错误。
- 已登录 Chrome 粘贴合成截图，在富文本中画箭头和方框并保存，新图片为 800×450；Markdown 中同图出现两次时只替换第二张。
- 在“管理人员”内部类别通过真实编辑器创建合成测试话题 `112`，发布后两张图片正确显示，原图与标注图链接分别保留；本测试不使用成员原有内容。
- 390×844 浏览器视口可以打开画布、画箭头并取消，页面宽度 390，无水平溢出，保存与取消按钮都在可见区域；取消不改变帖子版本和图片。
- 证据在 `outputs/image-annotator-20261011/`；移动视口检查不代表 iOS/Android 真机验收。

正式主题中再次打开绘图、绘制箭头和方框并取消，浏览器未捕获 console error。测试话题 `112` 已通过原生 `PostDestroyer` 软删除，保留可恢复记录和截图；没有改动成员原有帖子。成功标注上传共两张（`92`、`93`），取消不新增标注上传。

更新助手发布了 [使用指南](https://blackroom.qzz.io/t/topic/113) 与 [更新公告](https://blackroom.qzz.io/t/topic/114)，均在“网站反馈”，分别带“使用指南”“功能更新”标签。教程引用已保存的合成示例图（上传 `92`），浏览器显示正确，公告与教程互链。公告原生全站置顶截止北京时间 2026-10-18 01:33:15；当前用户读完后仍遵循原有的个人自动取消置顶行为。
