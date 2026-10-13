# 头像上传裁剪

源码在 `themes/blackroom-avatar-crop/`，使用独立主题组件，不修改 Discourse 核心或数据库结构。运行容器是 Docker context `nas` 的 `app`。

## 用户流程与范围

偏好设置 → 帐户 → 个人资料照片 → 上传 → 选图 → 拖动或方向键移动 → 滑块缩放 → 确认上传 → 保存变更。

裁剪在浏览器完成，圆形预览对应正方形 PNG 的圆形显示区域。浏览器输出为 512×512 静态 PNG，服务器继续按原生头像规则缩放（本次回查存储尺寸为 288×288）；动画图片裁剪后为静态头像。确认上传只上传裁剪结果，仍须在原头像窗口点击“保存变更”才会切换头像。取消或 Esc 不上传。

复用原有文件校验、Uppy 上传接口、CSRF 和服务端头像权限，不扩大允许上传头像的群组。组件覆盖普通头像上传和注册流程的延迟选图入口。原始图片在浏览器内使用 Blob URL，关闭后释放。

## 部署与回退

组件名称为 `BlackRoom Avatar Crop`，本站导入后的 ID 为 `1`。导入本地目录使用 Discourse 原生方法：

```ruby
theme = RemoteTheme.import_theme_from_directory(directory, theme_id: 1)
```

更新已有组件时必须指定 `theme_id`，防止重复创建。先检查所有 `theme_fields` 的编译错误，再在管理员独立标签页通过 `?preview_theme_id=1` 验证，最后关联到 Foundation 和 Horizon。无需重启或重建容器，已有页面刷新后生效。

回退时仅在这两个父主题中移除组件 ID `1`，保留其他组件、主题与上传文件。保留组件源码和关联变更前的快照，不删除用户头像。

2026-10-07 已关联到 Foundation（`-1`）和 Horizon（`-2`）。持久源码为容器内 `/shared/state/avatar-crop-20261007/source/`，关联变更前快照为 `/shared/state/avatar-crop-20261007/parents-before.json`。使用 `parent.child_theme_ids = parent.child_theme_ids - [1]` 后 `parent.save!` 可移除本组件并保留其他关联。

## 检查

本地几何检查：

```sh
node themes/blackroom-avatar-crop/check.mjs
```

浏览器检查中文文字、拖动、缩放、方向键、Tab、Esc、取消和确认上传，并核对取消没有上传、确认后结果为正方形。使用合成测试图，不保存到用户原有头像。移动尺寸检查属于浏览器响应式验收，不代表 iOS/Android 真机通过。

本机系统 Ruby 不能运行 `bin/lint`（缺少 `Array#filter_map`）。已有生产前端工具可执行相关 ESLint、Prettier 和 Stylelint；不安装额外依赖。生产升级后须重新核对 `avatar-uploader.chooseImage`、`modal/avatar-selector.filesPicked`、`d-modal.handleDocumentKeydown` 和 Uppy 的 `addFiles` 接口。

2026-10-07 验证结果：几何检查、相关 ESLint/Stylelint 和 Prettier 通过，主题编译无错误。已登录 Chrome 的本站组件预览中验证中文、鼠标拖动、1–4 倍缩放、方向键、Tab、Esc、取消按钮与真实上传接口；取消没有新增上传，确认上传返回文件 ID `45`，回查为正方形，未保存该合成图片为用户头像。实际文件选择入口另有用户自行选图的页面证据。验收期间临时使用预览专用合成图入口，启用前已恢复正式源码，该入口不随组件交付。

390×844 浏览器视口中窗口与页面均无水平溢出；[裁剪窗口截图](screenshots/avatar-crop-mobile.jpg)使用合成图片。普通正式账户页面的头像入口正常，未观察到浏览器错误，容器启动时间保持连续。注册延迟选图路径已接入但未创建真实用户验收；iOS/Android 真机尚未验证。
