# 官方 AI Helper 标签推荐

2026-10-11 启用官方 Discourse AI Helper 的编辑器建议，普通登录成员（含 TL0）可使用。标签保持可选，由作者决定是否采纳；没有开启发布后自动打标签，也没有修改现有主题标签。

## 成员操作

1. 新建话题，选择可以发帖的分区，先写正文（超过 40 个字符）。
2. 打开“可选标签…”下拉框，点击“显示 AI 建议”。
3. 等待建议出现，点击适合内容的标签，可选择多个。已选择的标签会从建议列表移除。
4. 检查标签后照常发布。可返回普通列表搜索标签，不需要采纳每个建议。

Markdown 与富文本共用原生标签选择器。推荐依赖站内已打标签的相似主题，仍可能混入常用但不相关的标签；正文太短、参考内容不足或模型暂不可用时，手动选标签即可。标签组和分区允许标签沿用服务端检查。

## 模型与设置

- 原生 AI 插件已安装，本次无核心源码修改、数据库迁移或 Discourse 重建/重启。
- NAS 原有 Ollama 新增 `bge-m3`（约 1.16 GB）及共享权重的 `blackroom-tags-bge-m3` 别名，参数为 CPU、4 线程、2048 上下文。
- `EmbeddingDefinition` ID 1，名称“BlackRoom 本地标签推荐 BGE-M3”，1024 维、余弦距离、`BgeM3Tokenizer`，输入上限 1024 token。使用官方 `open_ai` provider 协议，实际目标为 NAS 本地受认证代理 `http://172.17.0.1:11435/v1/embeddings`，不向 OpenAI 发送正文。
- `ai_embeddings_selected_model=1`、`ai_embeddings_enabled=true`，原生历史补齐每批 10 个。首轮顺序生成全部 26 个已有带标签主题的向量，并建立官方 HNSW 索引；原生后台任务继续补齐其他普通主题。
- `ai_helper_enabled=true`、`ai_helper_enabled_features=suggestions`、`composer_ai_helper_allowed_groups=3|10`。`ai_default_llm_model=1` 复用原有本地模型，以满足 Helper 的原生校验；标签推荐本身使用向量模型。原生 suggestions 还包含分类和标题建议，本次重点验收标签流程，不承诺其他辅助功能效果。
- 私信 Helper、私信向量生成、逐帖向量、语义搜索和相关主题功能保持关闭；帖子阅读侧允许群组保留原值。

代理新增精确的 POST `/v1/embeddings` 路由，复用原有认证，仍只监听 Docker 网关。未认证调用返回 401，其他未允许路径返回 404，GET 不允许。原有精确地址与端口的 FinalDestination 连接例外已覆盖此连接，无需扩大 `allowed_internal_hosts`。配置在原路径写入，`nginx -t` 通过后平滑 reload。

## 验证证据

- 通过 Discourse 原生向量客户端实测中文合成内容，返回 1024 个有效数字；冷启动约 4.08 秒。Ollama 回读 `size_vram=0`，模型进程约 1.22 GB；代理资源限制不能视为模型限制。共享 Ollama 的请求和模型加载仍可能竞争资源。
- 已登录 Chrome 在真实 Markdown 发帖编辑器请求建议，列表包含“二维原画”“作画参考”“动画影像”“绘画基础”，同时出现常用栏目标签；选择“二维原画”和“作画参考”后正文不变。富文本切换保留所选标签并显示剩余建议；恢复原 Markdown 模式后舍弃本次合成草稿，没有发布验收帖。
- 事务内 TL0 非社团成员、动画社成员、文学社成员与管理员矩阵通过：均能取得允许使用的推荐，两社私有分区保持隔离。临时隐藏标签不出现在普通成员推荐中，临时分区标签白名单只返回允许标签。临时记录全部回滚，现有 `TopicTag` 关系未改变，私信配置仍关闭。
- 浏览器未捕获 console error/warn。截图和检查结果在 `outputs/ai-tags-20261011/`；服务端结果同时保留在 `/shared/state/ai-tags-20261011/service-check.json`。
- 普通成员矩阵是服务端事务验收，浏览器使用现有管理员会话；未代替真实学生账号操作或手机真机验收。没有对推荐准确率作统计保证。

## 回退与持久化

配置前快照在 NAS `/shared/state/ai-tags-20261011/settings-before.json`（0600）；代理原配置在 `/home/muwei/blackroom-ai-tags-20261011/nginx.before.conf`（0600）。凭据只在 NAS 原受保护配置和模型记录中复用，没有写入本机或文档。

先关闭 `ai_helper_enabled` 与 `ai_embeddings_enabled`，再通过 `SiteSetting.set_and_log` 恢复快照中其他字段，最后恢复两个开关的原值，避免原生依赖校验阻止恢复。保留模型定义、模型文件和向量数据，不删除帖子或恢复数据库。

如需撤回代理路由，用原配置内容覆盖现有 `/home/muwei/blackroom-ollama-proxy/nginx.conf`，再执行原部署的 `nginx -t -c /config/nginx.conf` 与 `nginx -s reload -c /config/nginx.conf`。配置有受保护凭据，不打印全文；不要更换挂载文件 inode 后误认为容器已读取新文件。

模型与参数保存在原有 Ollama 数据位置，设置及向量保存在 Discourse 数据库。恢复整站须包含这些依赖，现有整站备份不能自动等同于已覆盖新增模型的恢复演练。

## 更新公告与教程

2026-10-11 已由原生更新助手发布并在浏览器验收：[更新公告](https://discourse.muwei.xyz/t/topic/136)、[成员操作指南](https://discourse.muwei.xyz/t/topic/135)。作者为 `blackroom_update_bot`，分区为“网站反馈”，分别带“功能更新”和“使用指南”标签，双向链接正确。公告全站置顶截止北京时间 2026-10-18 15:48:23，已回读一项原生取消置顶任务。发布制品和截图在 `outputs/blackroom-updates/ai-tags-20261011/`。

`bin/lint --fix` 已运行，但项目未为 Markdown 和这些输出 JSON 配置核心 linter，返回 Nothing was linted；清单 JSON、服务端结果断言与原生发布器预览通过。没有将此称为全库 lint 或源码测试通过。

## 官方资料

- [编辑器内联 AI 建议](https://meta.discourse.org/t/inline-integration-of-ai-suggestions-in-composer/405394)
- [Discourse AI Helper](https://meta.discourse.org/t/discourse-ai-helper/283943)
- [Ollama BGE-M3](https://ollama.com/library/bge-m3)
- [Ollama OpenAI-compatible API](https://docs.ollama.com/api/openai-compatibility)
