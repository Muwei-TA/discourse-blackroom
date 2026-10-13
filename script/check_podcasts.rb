# frozen_string_literal: true

category = Category.find_by!(slug: "podcasts")
unless (%w[mp3 m4a ogg opus wav] - SiteSetting.authorized_extensions.split("|")).empty?
  raise "Audio extensions missing"
end
raise "Unexpected upload limit" unless SiteSetting.max_attachment_size_kb == 65_536
raise "Anonymous category access" if Guardian.new.can_see_category?(category)
raise "Posting template missing" if category.topic_template.exclude?("## 收听本期")

# Database probes must not enqueue notifications or leave Redis duplicate-body keys.
PostCreator.prepend(
  Module.new do
    def store_unique_post_key
    end
  end,
)
matrix = []
ActiveRecord::Base.transaction do
  [0, 1].product(["blackbox_animation", "blacklight_lit", nil])
    .each do |level, group_name|
      username = "podcast_#{SecureRandom.hex(5)}"
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
                trust_level: level,
              },
            ],
            returning: %w[id],
          )
          .rows
          .first
          .first
      user = User.find(id)
      UserOption.create!(user: user)
    UserStat.create!(user: user, new_since: Time.zone.now)
      group_ids = [Group::AUTO_GROUPS[:trust_level_0]]
      group_ids << Group::AUTO_GROUPS[:trust_level_1] if level == 1
      group_ids << Group.find_by!(name: group_name).id if group_name
      group_ids.each do |group_id|
        GroupUser.insert_all!([{ group_id: group_id, user_id: id, owner: false }])
      end
      guardian = user.guardian
      access = {
        read: guardian.can_see_category?(category),
        publish: guardian.can_create_topic_on_category?(category),
        reply: guardian.can_create_post_on_topic?(category.topic),
      }
      raise "Member permissions failed: #{group_name}, TL#{level}" unless access.values.all?

      creator =
        PostCreator.new(
          user,
          category: category.id,
          title: "播客权限验收 #{username}",
          raw: "这是回滚事务内的播客发布与讨论验收。#{SecureRandom.hex(8)}",
          skip_jobs: true,
          skip_rate_limits: true,
        )
      post = creator.create
      raise creator.errors.full_messages.join("; ") unless post&.persisted? && creator.errors.empty?
      reply_creator =
        PostCreator.new(
          user,
          topic_id: post.topic_id,
          raw: "这是回滚事务内的收听讨论回复。#{SecureRandom.hex(8)}",
          skip_jobs: true,
          skip_rate_limits: true,
        )
      reply = reply_creator.create
      unless reply&.persisted? && reply_creator.errors.empty?
        raise reply_creator.errors.full_messages.join("; ")
      end
      raise "Own editing unavailable" unless guardian.can_edit_post?(post)
      if guardian.can_edit_post?(category.topic.first_post)
        raise "Member can edit category description"
      end

      Group
        .where(name: %w[blackbox_animation blacklight_lit])
        .each do |club|
          private_category = Category.find_by!(name: club.full_name)
          unless guardian.can_see_category?(private_category) == (club.name == group_name)
            raise "Club privacy changed"
          end
        end
      matrix << {
        trust_level: level,
        club: group_name || "no club",
        access: access,
        post_created: true,
        reply_created: true,
      }
    end
  admin = User.where(admin: true, active: true).where("id > 0").first!.guardian
  unless admin.can_see_category?(category) && admin.can_create_topic_on_category?(category)
    raise "Admin access missing"
  end
  raise ActiveRecord::Rollback
end
puts JSON.generate(
       matrix: matrix,
       anonymous_denied: true,
       admin_access: true,
       temporary_data_rolled_back: true,
     )
