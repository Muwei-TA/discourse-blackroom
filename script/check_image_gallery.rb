# frozen_string_literal: true

category = Category.find_by!(slug: "image-gallery")
component = Theme.find_by!(name: "Topic List Thumbnails")
raise "Unexpected default layout" unless component.get_setting(:default_thumbnail_mode) == "none"
raise "Unexpected masonry scope" unless component.get_setting(:masonry_categories) == category.id.to_s
raise "Mobile thumbnails disabled" unless component.get_setting(:mobile_thumbnails)
raise "Theme attachment missing" unless Theme.where(component: false).all? { |t| t.child_theme_ids.include?(component.id) }

matrix = []
ActiveRecord::Base.transaction do
  ["blackbox_animation", "blacklight_lit", nil].each do |group_name|
    username = "gallery_probe_#{SecureRandom.hex(5)}"
    user_id = User.insert_all!([{ username: username, username_lower: username,
      active: true, approved: true, admin: false, moderator: false, trust_level: 1 }], returning: %w[id]).rows.first.first
    user = User.find(user_id)
    if group_name
      GroupUser.insert_all!([{ group_id: Group.find_by!(name: group_name).id, user_id: user.id, owner: false }])
    end
    access = { visible: user.guardian.can_see_category?(category), can_post: user.guardian.can_post_in_category?(category) }
    raise "Gallery member access failed: #{group_name}" unless access.values.all?
    private_access = Category.where(id: [38, 39, 45]).map { |c| [c.id, user.guardian.can_see_category?(c)] }.to_h
    expected = { 38 => group_name == "blackbox_animation", 39 => group_name == "blacklight_lit", 45 => group_name == "blackbox_animation" }
    raise "Existing club isolation changed" unless private_access == expected
    matrix << { role: group_name || "no club", gallery: access, private_categories: private_access }
  end
  guardian = User.find(1).guardian
  raise "Admin access failed" unless guardian.can_see_category?(category) && guardian.can_post_in_category?(category)
  raise ActiveRecord::Rollback
end
puts JSON.generate(checks: matrix, admin_access: true, temporary_accounts_rolled_back: true)
