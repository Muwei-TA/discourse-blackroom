# frozen_string_literal: true

category = Category.find_by!(slug: "acg-daily")
bot = User.find_by!(username: "discobot")
raise "Unexpected publishing identity" unless bot.id == -2
raise "Bot missing posting permission" unless bot.guardian.can_create_topic_on_category?(category)
raise "Category unexpectedly restricted" if category.read_restricted
snapshot_path = Dir["/shared/state/acg-daily-before-*.json"].max
snapshot = JSON.parse(File.read(snapshot_path))
unless CategoryGroup
         .where(category_id: snapshot.fetch("category_ids"))
         .order(:category_id, :group_id)
         .pluck(:category_id, :group_id, :permission_type) == snapshot.fetch("permissions")
  raise "Existing permissions changed"
end
clubs = %w[blackbox_animation blacklight_lit].map { |name| Group.find_by!(name: name) }
private_categories = clubs.map { |group| Category.find_by!(name: group.full_name) }
matrix = []
ActiveRecord::Base.transaction do
  3.times do |index|
    username = "acg_probe_#{SecureRandom.hex(5)}"
    id =
      User
        .insert_all!(
          [
            {
              username: username,
              username_lower: username,
              active: true,
              approved: true,
              admin: false,
              moderator: false,
              trust_level: 1,
            },
          ],
          returning: %w[id],
        )
        .rows
        .first
        .first
    user = User.find(id)
    if index < clubs.size
      GroupUser.insert_all!([{ group_id: clubs[index].id, user_id: id, owner: false }])
    end
    unless user.guardian.can_see_category?(category) &&
             user.guardian.can_post_in_category?(category)
      raise "Member cannot see/reply"
    end
    actual = private_categories.map { |c| user.guardian.can_see_category?(c) }
    unless actual == private_categories.each_index.map { |i| i == index }
      raise "Private club isolation changed"
    end
    matrix << {
      member: index < clubs.size ? clubs[index].name : "non_member",
      daily_visible: true,
      daily_reply: true,
      private_clubs: actual,
    }
  end
  raise ActiveRecord::Rollback
end
admin = User.where(admin: true, active: true).first!
raise "Admin lost access" unless admin.guardian.can_see_category?(category)

date = Time.current.in_time_zone("Asia/Shanghai").to_date
topics = Topic.where(category_id: category.id, user_id: bot.id, title: "ACG 日报｜#{date}")
raise "Expected exactly one daily topic" unless topics.count == 1
post = topics.first.first_post
if post.cooked.exclude?("www.animenewsnetwork.com") || post.cooked.exclude?("www.gcores.com")
  raise "Body was not cooked"
end
puts(
  {
    checks: matrix,
    admin_access: true,
    existing_permissions_unchanged: true,
    publishing_identity: bot.username,
    daily_count: topics.count,
    topic_url: topics.first.url,
    temporary_accounts_rolled_back: true,
  }.to_json,
)
