# BlackRoom 播客主题组件

仅为播客类别 `49` 和节目话题提供专用 UI；类别说明话题 `115` 保留原生正文入口。使用 Discourse 的 PluginOutlet、话题列表 transformer、原生编辑器、书签与回复服务，无核心源码修改或额外依赖。

节目封面来自原生 `topic.image_url`；缺图时使用标题生成文字封面。频道按当前原生筛选和加载顺序展示；输入框仅过滤已加载标题，全量查找链接进入原生搜索。正文音频通过认证话题 JSON 或已加载首帖的 cooked 标记读取，只接受 HTTP(S)。音频按需加载，不批量请求节目正文。

播放器状态仅保留在当前 SPA 页面实例，站内跳转不中断；刷新、关闭标签页和切换浏览器不保留状态。选择新节目会停止旧音频；原帖播放器开始播放时关闭底部播放器。时间轴只解析「时间轴」「章节」「Chapters」「Timestamps」标题之下的换行或列表，遇到下一个标题停止，非法时间忽略。

源码持久化在 NAS `/shared/state/podcast-ui-20261011/source`，导入与回退脚本为本项目 `script/install_podcast_ui.rb`，线上副本 `/shared/state/podcast-ui-20261011/install.rb`。

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner /shared/state/podcast-ui-20261011/install.rb'
```

不带参数仅导入/更新组件，已关联组件的更新会生效；首次未关联时可用 `?preview_theme_id=5` 独立预览。`--enable` 关联现有 Foundation 和 Horizon，`--disable` 只解除本组件关联，保留节目、附件、用户、其他组件与源文件。组件 ID `5` 必须在现场核对，脚本按名称查找，避免重复创建。

验证与维护记录见 `docs/operations/podcasts.md`。本地解析检查页面 `spec/check.html` 不导入线上主题；本机使用支持 ES modules 的本地 HTTP 服务打开它。
