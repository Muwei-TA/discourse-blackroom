# frozen_string_literal: true

admin = User.where(admin: true, active: true).where("id > 0").order(:id).first!
I18n.locale = SiteSetting.default_locale
if Category.exists?(slug: "podcasts") || Category.exists?(name: "播客")
  raise "Inspect the existing podcast category first"
end

stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
snapshot_path = "/shared/state/podcasts-before-#{stamp}.json"
snapshot = {
  authorized_extensions: SiteSetting.authorized_extensions,
  max_attachment_size_kb: SiteSetting.max_attachment_size_kb,
  svg_icon_subset: SiteSetting.svg_icon_subset,
  login_required: SiteSetting.login_required,
  invite_only: SiteSetting.invite_only,
  category_ids: Category.pluck(:id),
  permissions:
    CategoryGroup.order(:category_id, :group_id).pluck(:category_id, :group_id, :permission_type),
  sidebar: SidebarSectionLink.order(:id).pluck(:id, :position),
}
File.write(snapshot_path, JSON.pretty_generate(snapshot), mode: "wx", perm: 0o600)

result = nil
ActiveRecord::Base.transaction do
  category =
    CategoryCreator.create(
      admin.guardian,
      {
        name: "播客",
        slug: "podcasts",
        color: "B06B47",
        text_color: "FFFFFF",
        description:
          "成员的声音与故事。每期节目发布一个话题，上传音频或提供可直接播放的音频链接，附上简介、主创和时间轴；收听后在话题下回复交流。仅已登录成员可访问。请分享原创或获授权的内容，不上传私有社团录音或个人敏感信息。",
        permissions: {
          trust_level_0: :full,
          staff: :full,
        },
        topic_template: <<~MD,
      ## 收听本期
      点击编辑器的上传按钮添加音频（推荐 MP3，单文件不超过 64 MB），或将音频直链单独放在一行。

      ## 本期简介
      这期聊什么？适合谁听？

      ## 主创与时长
      主播／嘉宾：
      节目时长：
      原创／授权来源：

      ## 时间轴（可选）
      00:00 开场

      ## 一起讨论
      你希望听众聊聊什么？
    MD
      },
    )
  raise category.errors.full_messages.join("; ") unless category.persisted?

  SiteSetting.authorized_extensions =
    (snapshot[:authorized_extensions].split("|") + %w[mp3 m4a ogg opus wav]).uniq.join("|")
  SiteSetting.max_attachment_size_kb = 65_536
  SiteSetting.svg_icon_subset =
    (snapshot[:svg_icon_subset].split("|") + ["headphones"]).uniq.join("|")

  community = SidebarSection.find_by!(section_type: :community)
  url = SidebarUrl.create!(name: "播客", value: category.url, icon: "headphones", segment: :primary)
  community.sidebar_section_links.create!(linkable: url)
  order = community.sidebar_urls.where.not(id: url.id).pluck(:id)
  gallery_position = order.index(SidebarUrl.find_by(name: "图文广场")&.id)
  order.insert(gallery_position ? gallery_position + 1 : 0, url.id)
  community.apply_links_order!(order)
  StaffActionLogger.new(admin).log_update_public_sidebar_section(community)

  unless CategoryGroup
           .where(category_id: snapshot[:category_ids])
           .order(:category_id, :group_id)
           .pluck(:category_id, :group_id, :permission_type) == snapshot[:permissions]
    raise "Existing permissions changed"
  end
  unless SiteSetting.login_required == snapshot[:login_required] &&
           SiteSetting.invite_only == snapshot[:invite_only]
    raise "Registration policy changed"
  end
  result = {
    category_id: category.id,
    url: category.url,
    definition_topic_id: category.topic_id,
    sidebar_url_id: url.id,
    snapshot: snapshot_path,
  }
end

Site.clear_cache
MessageBus.publish("/refresh-sidebar-sections", nil)
File.write(
  "/shared/state/podcasts-created-#{stamp}.json",
  JSON.pretty_generate(result),
  perm: 0o600,
)
puts JSON.generate(result)
