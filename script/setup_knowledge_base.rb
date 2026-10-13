# frozen_string_literal: true

admin = User.find(1)
raise "Knowledge base already exists; inspect before changing it" if Category.exists?(slug: "knowledge-base")

snapshot_path = "/shared/state/knowledge-base-settings-before-20261007.json"
snapshot = {
  categories: Category.order(:id).pluck(:id, :name, :parent_category_id),
  permissions: CategoryGroup.order(:category_id, :group_id).pluck(:category_id, :group_id, :permission_type),
  default_categories_muted: SiteSetting.default_categories_muted,
  themes: Theme.where(component: false).map { |theme| [theme.id, theme.child_theme_ids] },
}
File.write(snapshot_path, JSON.pretty_generate(snapshot), mode: "wx", perm: 0o600)

result = nil
ActiveRecord::Base.transaction do
  category = CategoryCreator.create(admin.guardian, {
    name: "知识库", slug: "knowledge-base", color: "0088CC", text_color: "FFFFFF",
    description: "按领域和专题整理的学习资料与社团手册，请从独立的知识库入口浏览。",
    permissions: { everyone: :readonly, staff: :full },
  })
  raise category.errors.full_messages.join("; ") unless category.persisted?

  previous_muted = SiteSetting.default_categories_muted
  SiteSetting.default_categories_muted = (previous_muted.split("|") + [category.id.to_s]).uniq.join("|")
  SiteSettingUpdateExistingUsers.default_categories("default_categories_muted", SiteSetting.default_categories_muted, previous_muted)

  create_topic = lambda do |title, raw, tags = []|
    creator = PostCreator.new(admin, title: title, raw: raw, category: category.id, tags: tags, skip_jobs: true)
    post = creator.create
    raise creator.errors.full_messages.join("; ") unless post&.persisted?
    TopicUser.change(admin.id, post.topic_id, notification_level: TopicUser.notification_levels[:regular])
    post.topic
  end

  guide = create_topic.call("知识库使用与维护指南", <<~MD)
    知识库用于保存整理后的知识、教程和手册。讨论、提问和日常交流仍在原有板块进行。

    ## 浏览与搜索
    从“知识库”入口选择领域，再进入专题与具体条目。文档侧栏可以切换目录；在站点搜索中加入 `in:docs` 可限定搜索知识库。

    ## 贡献与维护
    正文目前由站点管理人员维护。成员可以在[资源共享](/c/36)提交资料或改进建议，注明所属领域、专题与来源，由维护者整理入库。

    新增条目时，先在“知识库”内容分区创建文章，再编辑相应领域目录，添加文章链接。修改领域目录不需要新增论坛板块。

    ## 条目建议结构
    标题应明确说明问题或用途。正文可按“适用对象、核心内容、操作步骤、参考来源、更新日期”组织；引用资料请注明来源。

    ## 资料权限
    此处资料向站内成员共享。私有社团资料请保留在各自的私有分区，不要复制到共享知识库，也不要在共享目录暴露私有文章标题或链接。
  MD

  domains = [
    ["动画与影像", "动画影像", ["动画基础", "制作工具与工作流", "影像分析"]],
    ["文学与写作", "文学写作", ["叙事与写作方法", "阅读与作品研究", "编辑与投稿"]],
    ["社团工作", "社团工作", ["活动策划", "协作与交接", "资料整理"]],
  ].map do |name, tag, subjects|
    raw = "这里按专题整理#{name}领域的知识。当前已建立目录，具体条目待整理入库。\n\n"
    subjects.each { |subject| raw += "## #{subject}\n\n尚未收录条目。\n\n" }
    raw += "## 提交与维护\n\n请参考[知识库使用与维护指南](#{guide.relative_url})。\n"
    [name, create_topic.call("#{name} · 专题目录", raw, [tag])]
  end

  root_raw = "欢迎来到 BlackRoom 知识库。这里按领域、专题和条目组织整理后的资料。\n\n"
  domains.each { |name, topic| root_raw += "## #{name}\n\n- [专题目录](#{topic.relative_url})\n\n" }
  root_raw += "## 使用与贡献\n\n- [使用与维护指南](#{guide.relative_url})\n"
  root = create_topic.call("知识库 · 领域导航", root_raw)
  DocCategories::CategoryIndexManager.new(category).assign!(root.id)
  DocCategories::IndexStructureRefresher.new(category.id).refresh!
  SiteSetting.doc_categories_enabled = true

  community = SidebarSection.find_by!(section_type: :community)
  url = SidebarUrl.create!(name: "知识库", value: root.relative_url, icon: "book", segment: :primary)
  community.sidebar_section_links.create!(linkable: url)
  community.apply_links_order!([url.id] + community.sidebar_urls.where.not(id: url.id).pluck(:id))
  StaffActionLogger.new(admin).log_update_public_sidebar_section(community)

  result = { category_id: category.id, index_topic_id: root.id, guide_topic_id: guide.id,
    domains: domains.to_h.transform_values(&:id), sidebar_url_id: url.id, url: root.url }
end

Site.clear_cache
MessageBus.publish("/refresh-sidebar-sections", nil)
File.write("/shared/state/knowledge-base-created-20261007.json", JSON.pretty_generate(result), perm: 0o600)
puts JSON.generate(result)
