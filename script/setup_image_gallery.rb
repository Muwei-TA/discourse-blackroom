# frozen_string_literal: true

admin = User.find(1)
I18n.locale = SiteSetting.default_locale
source = "https://github.com/discourse/discourse-topic-thumbnails"
raise "Inspect the existing gallery before configuring it" if Category.exists?(slug: "image-gallery")

stamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
snapshot_path = "/shared/state/image-gallery-before-#{stamp}.json"
snapshot = {
  category_ids: Category.pluck(:id),
  permissions: CategoryGroup.order(:category_id, :group_id).pluck(:category_id, :group_id, :permission_type),
  themes: Theme.all.map { |theme| { id: theme.id, children: theme.child_theme_ids } },
  sidebar: SidebarSectionLink.order(:id).pluck(:id, :position),
}
File.write(snapshot_path, JSON.pretty_generate(snapshot), mode: "wx", perm: 0o600)

raise "Thumbnail component already exists; inspect its settings" if RemoteTheme.exists?(remote_url: source)
component = RemoteTheme.import_theme(source, admin)
raise component.errors.full_messages.join("; ") unless component.persisted?
raise "Expected a theme component" unless component.component?

result = nil
ActiveRecord::Base.transaction do
  category = CategoryCreator.create(admin.guardian, {
    name: "图文广场", slug: "image-gallery", color: "8759C9", text_color: "FFFFFF",
    description: "展示摄影、插画、设计和活动图文。每个作品创建一个话题，在首帖上传图片并附上说明；第一张图片默认作为封面。请只分享可在站内共享的作品，私有社团内容保留在原分区。",
    permissions: { everyone: :full },
  })
  raise category.errors.full_messages.join("; ") unless category.persisted?

  component.update_setting(:default_thumbnail_mode, "none")
  component.update_setting(:masonry_categories, category.id.to_s)
  component.update_setting(:mobile_thumbnails, true)
  component.save!
  Theme.where(component: false).each { |theme| theme.add_relative_theme!(:child, component) }

  community = SidebarSection.find_by!(section_type: :community)
  url = SidebarUrl.create!(name: "图文广场", value: category.url, icon: "images", segment: :primary)
  community.sidebar_section_links.create!(linkable: url)
  previous_order = community.sidebar_urls.where.not(id: url.id).pluck(:id)
  community.apply_links_order!([previous_order.shift, url.id, *previous_order].compact)
  StaffActionLogger.new(admin).log_update_public_sidebar_section(community)

  raise "Default layout changed" unless component.get_setting(:default_thumbnail_mode) == "none"
  raise "Gallery mode missing" unless component.get_setting(:masonry_categories) == category.id.to_s
  raise "Existing permissions changed" unless CategoryGroup.where(category_id: snapshot[:category_ids]).order(:category_id, :group_id).pluck(:category_id, :group_id, :permission_type) == snapshot[:permissions]
  result = { category_id: category.id, url: category.url, theme_id: component.id,
    sidebar_url_id: url.id, source_commit: component.remote_theme.local_version, snapshot: snapshot_path }
end

Site.clear_cache
Theme.clear_cache!
MessageBus.publish("/refresh-sidebar-sections", nil)
File.write("/shared/state/image-gallery-created-#{stamp}.json", JSON.pretty_generate(result), perm: 0o600)
puts JSON.generate(result)
