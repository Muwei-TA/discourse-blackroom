# frozen_string_literal: true

names = ["blackbox_animation", "blacklight_lit"]
groups = names.map { |name| Group.find_by!(name: name) }
categories = groups.map { |group| Category.find_by!(name: group.full_name) }
matrix = []

ActiveRecord::Base.transaction do
  3.times do |index|
    username = "club_probe_#{SecureRandom.hex(5)}"
    user_id = User.insert_all!([{ username: username, username_lower: username,
      active: true, approved: true, admin: false, moderator: false, trust_level: 1 }], returning: %w[id]).rows.first.first
    user = User.find(user_id)
    if index < groups.length
      GroupUser.insert_all!([{ group_id: groups[index].id, user_id: user.id, owner: false }])
    end
    guardian = user.guardian
    actual = categories.map do |category|
      { visible: guardian.can_see_category?(category), can_post: guardian.can_post_in_category?(category) }
    end
    expected = categories.each_index.map { |position| { visible: position == index, can_post: position == index } }
    raise "Club isolation failed for membership #{index}: #{actual}" unless actual == expected
    matrix << { membership: index < groups.length ? groups[index].full_name : "no club", access: actual }
  end
  admin_guardian = User.find(1).guardian
  raise "Admin lost access" unless categories.all? { |category| admin_guardian.can_see_category?(category) && admin_guardian.can_post_in_category?(category) }
  raise ActiveRecord::Rollback
end
puts JSON.generate(checks: matrix, admin_access: true, temporary_accounts_rolled_back: true)
