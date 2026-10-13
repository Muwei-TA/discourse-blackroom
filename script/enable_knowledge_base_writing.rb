# frozen_string_literal: true

admin = User.find(1)
category = Category.find(46)
topic_ids = [54, 55, 56, 57, 58]
posts = Post.where(topic_id: topic_ids, post_number: 1).order(:topic_id).to_a
raise "Knowledge base inventory changed" unless category.slug == "knowledge-base" && posts.size == 5 && posts.all? { |post| post.topic.category_id == category.id }
path = "/shared/state/knowledge-base-writing-before-20261007.json"
File.write(path, JSON.pretty_generate({
  permissions: category.permissions_params,
  topic_template: category.topic_template,
  posts: posts.map { |post| { id: post.id, topic_id: post.topic_id, raw: post.raw, locked_by_id: post.locked_by_id } },
}), mode: "wx", perm: 0o600)

ActiveRecord::Base.transaction do
  updated = CategoryUpdater.update(admin.guardian, category, permissions: { everyone: :full, staff: :full }, topic_template: <<~MD)
    ## 适用对象与问题
    这篇文章帮助谁解决什么问题？

    ## 核心内容
    请写下知识要点、操作步骤或经验。

    ## 参考来源
    注明资料来源；原创经验可注明实践条件与验证结果。

    ## 限制与更新
    说明适用范围、已知限制和更新日期。
  MD
  raise category.errors.full_messages.join("; ") unless updated

  guide = posts.find { |post| post.topic_id == 54 }
  guide_raw = <<~MD
    知识库保存整理后的知识、教程和手册。每位已登录、具有正常发帖权限的成员都可以撰写文章；讨论、提问和日常交流仍可使用原有板块。

    ## 撰写文章
    1. 点击知识库目录中的[新建文章](/new-topic?category_id=46)，或从领域目录点击“在本领域写文章”。
    2. 编辑器会预选“知识库”分区；从领域入口写作时也会预选领域标签。
    3. 填写清楚的标题，修改正文模板，选择“动画影像”“文学写作”或“社团工作”等合适的标签。
    4. 点击编辑器的发布按钮。文章发布后可在[全部知识文章](/c/knowledge-base/46)找到；原有反垃圾、审核与发帖限制仍适用。

    ## 修改与补充
    作者可使用文章下方的编辑按钮修改自己的正文，遵循站点原有编辑权限与时限。普通成员可以回复提出补充，不默认开放多人任意修改正文。

    目录和本指南的正文由管理人员维护。文章不会自动出现在专题目录中；发布后可在相应领域目录下回复，说明希望归入的专题，由管理员添加链接。目录中的回复不会自动变成目录条目。

    ## 浏览与搜索
    从领域目录进入专题与条目；文档侧栏支持目录筛选。站点搜索中加入 `in:docs` 可限定搜索知识库。尚未编入目录的文章仍可从“全部知识文章”查找。

    ## 内容与权限
    标题应说明问题或用途，正文建议包括适用对象、核心内容、操作步骤、参考来源和更新信息。

    此处资料向站内成员共享。私有社团资料请保留在各自的私有分区，不要复制到共享知识库，也不要在共享目录暴露私有文章标题或链接。
  MD
  raise "Guide revision failed" unless PostRevisor.new(guide).revise!(admin, { raw: guide_raw }, silent: true)

  tags = { 55 => "动画影像", 56 => "文学写作", 57 => "社团工作" }
  posts.each do |post|
    next unless tags.key?(post.topic_id)
    raw = post.raw.split("## 提交与维护").first
    raw += "## 写作与维护\n\n[在本领域写文章](/new-topic?category_id=46&tags=#{CGI.escape(tags.fetch(post.topic_id))}) · [浏览全部知识文章](/c/knowledge-base/46)\n\n"
    raw += "发布文章后，可在本目录下回复并注明所属专题，由管理员将文章链接编入目录。详见[知识库使用与维护指南](/t/topic/54)。\n"
    raise "Domain revision failed" unless PostRevisor.new(post).revise!(admin, { raw: raw }, silent: true)
  end

  root = posts.find { |post| post.topic_id == 58 }
  raw = root.raw.sub("## 动画与影像", "[新建文章](/new-topic?category_id=46) · [全部知识文章](/c/knowledge-base/46)\n\n## 动画与影像")
  raise "Index revision failed" unless PostRevisor.new(root).revise!(admin, { raw: raw }, silent: true)
  posts.each { |post| PostLocker.new(post, admin).lock unless post.locked? }
end

Site.clear_cache
puts JSON.generate(category_id: category.id, permissions: category.reload.permissions_params, locked_directory_topics: topic_ids, template_enabled: category.topic_template.present?)
