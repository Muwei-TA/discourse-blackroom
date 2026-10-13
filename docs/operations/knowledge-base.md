# BlackRoom 知识库

## 内容与权限

2026-10-07 配置：知识库使用独立导航入口，底层只有一个专用内容分区，不改动已有讨论与社团分区。

- 入口：`https://discourse.muwei.xyz/t/topic/58`。
- 内容分区：知识库，ID `46`，slug `knowledge-base`。
- 总目录：话题 `58`；动画与影像、文学与写作、社团工作目录分别为 `55`、`56`、`57`。
- 使用与维护指南：话题 `54`。
- 领域标签：动画影像、文学写作、社团工作。
- 分区权限：`everyone: full`、`staff: full`。站点仍要求登录并仅接受邀请注册。
- 本次建立目录和维护指南，未编造或导入具体知识条目。

领域和专题通过目录文章组织，不为每个领域新增分区。新增正文后，将链接加入对应领域目录；增删领域时同时修改总目录。官方文档侧栏由总目录生成，当前提供领域入口；深入专题时通过领域文章的标题与链接浏览，不承诺无限层级的折叠树。

普通成员可创建文章、修改自己的正文并回复补充，遵循站点原有编辑时限、审核和反垃圾规则。总目录、领域目录和维护指南通过原生 PostLocker 锁定正文，由管理人员维护；目录下仍允许成员回复提出收录申请。具有站点既有高级编辑权限的受信成员仍遵循原生权限，未修改全站信任等级规则。共享目录不得包含私有社团资料及其标题、链接。私有资料继续使用原社团分区权限。

专用分区加入 `default_categories_muted`，并通过原生服务应用到没有显式偏好的现有用户；成员可自行调整订阅。默认讨论信息流不显示知识库目录，直接访问和文档搜索仍可使用。

初始化移除了新建目录文章给作者自动设置的关注状态，避免它覆盖分区静音；只处理本次新建知识库文章的作者订阅，没有改变原有文章订阅。

## 插件与展示

使用官方 [Discourse Doc Categories](https://meta.discourse.org/t/discourse-doc-categories/322376)，固定到提交 `ad921bb9e2767975bc725ce7ffa8b51d0bbe9938`。

- NAS 持久源码：`/home/muwei/discourse-docker-preview/plugins/discourse-doc-categories`。
- 当前容器源码：`/var/www/discourse/plugins/discourse-doc-categories`，首次通过复制安装。
- 部署 YAML 已添加构建安装命令及源码 volume；未来重建时使用持久源码。邮件插件的安装和 volume 保留。
- 插件新增 `doc_categories_indexes`、`doc_categories_sidebar_sections`、`doc_categories_sidebar_links` 三张索引表，已获得用户明确授权。
- `doc_categories_enabled` 开启；实验性的 simple mode 与旧 Docs 路径兼容功能保持默认关闭。
- 知识库入口使用原生 Community 侧栏链接，SidebarUrl ID `34`。
- 主题组件 `BlackRoom Knowledge Base`（ID `2`）附加到 Foundation 和 Horizon，用范围化 CSS 隐藏知识库分区的普通分类卡片与分类侧栏项。正文中的分区标识、管理后台与发帖分类选择保留；CSS 不承担访问控制。

主题源码保存在 `themes/blackroom-knowledge-base/`。更换专用分区 ID 时需同步组件的选择器。主题字段保存在数据库中，正常重启及重建仍可使用。

插件安装的资源流程必须包含 `assets:precompile`。仅执行 `assets:precompile:build_plugins` 会生成 JS，但不更新 Propshaft 发布清单，可能导致 `asset was not found in the load path` 和页面 500。

## 核验

`script/check_knowledge_base.rb` 检查目录与索引、原分区及权限不变、两个社团成员和非成员的发表、作者修改、回复权限，以及普通成员不能修改他人正文或目录、管理员维护权限。临时用户、文章、修改与回复均在事务内回滚；测试创建跳过通知任务和节流等待，保留权限及正文验证。这不替代真实学生登录验收。

```sh
docker --context nas exec -u discourse app bash -lc 'cd /var/www/discourse && bin/rails runner script/check_knowledge_base.rb'
```

本机 `bin/lint --fix` 因系统 Ruby 不支持 `Array#filter_map` 无法启动。Ruby 脚本使用语法检查与生产 Rails 检查，主题使用服务端编译和浏览器核验；不要将这些称为 lint 通过。

本次已核验登录管理员浏览器中的独立入口、文档侧栏、领域目录和目录筛选；分类页原有 9 个顶层分区仍可见，知识库分区卡片未显示。390×844 浏览器视口下正文与目录菜单正常，页面宽度和滚动宽度均为 390，无横向溢出；这不是手机真机验收。邮件适配器独立检查通过，未发送测试邮件。

截图保存在 `outputs/knowledge-base/`，包括桌面知识库、手机视口知识库和分类页。插件安装时出现过缺失资源清单导致的 500，补齐资源发布并重启后页面已恢复。

## 回退材料

- 变更前数据库快照：容器 `/shared/state/knowledge-base-before-20261007.dump`，对应 NAS 持久数据卷。该快照不包括上传文件，不是完整站点备份；不得自动恢复覆盖新数据。
- 配置与权限快照：`/shared/state/knowledge-base-settings-before-20261007.json`。
- 创建对象清单：`/shared/state/knowledge-base-created-20261007.json`。
- 部署 YAML 原件：`/home/muwei/discourse-docker-preview/state/knowledge-base-20261007/app.yml.before`，保持受保护权限，含凭据，不输出正文。

遇到插件故障先关闭 `doc_categories_enabled`。若插件本身阻碍启动，移出本次安装的插件目录、撤回其部署 hook/volume，再编译资源和重启；保留知识库文章及索引表，不删除业务数据。需要恢复数据库或删除内容时另行获得具体授权。

`script/setup_knowledge_base.rb` 是本次初始化脚本，检测到同名 slug 会停止，不用于覆盖已有知识库。初始化创建文章时跳过通知任务，没有发送真实邮件。

## 成员写作流程 — 2026-10-07

- 总目录新增“新建文章”和“全部知识文章”；每个领域目录新增“在本领域写文章”。
- 入口使用原生 `/new-topic?category_id=46`；领域入口附加 `tags` 参数，预选知识库和领域标签。
- 专用分区的 `topic_template` 提供适用对象、核心内容、参考来源、限制与更新四部分。
- 文章发布后可在全部知识文章中查看；管理员再将链接编入领域、专题目录。索引不会自动收录普通成员的新文章。
- 写作配置前快照：`/shared/state/knowledge-base-writing-before-20261007.json`，包括原权限、模板及五篇目录/指南正文和锁定状态。只恢复本次字段，不覆盖其他内容；正文通过 PostRevisor 修改，锁定通过 PostLocker 管理。
- 初始化脚本：`script/enable_knowledge_base_writing.rb`，仅执行一次，不重复运行覆盖用户后续编辑。

文档索引更新复用插件的后台任务，不在修改后同时手动刷新，以免两个更新竞争导致位置唯一性校验失败。
