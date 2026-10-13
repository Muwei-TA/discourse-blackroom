# frozen_string_literal: true

# Run with the production Rails environment as the discourse OS user.
require "json"

manifest =
  JSON.parse(
    File.read(ENV.fetch("BLACKROOM_GAMES_MANIFEST", "/shared/state/blackroom-games/games.json")),
  )
raise "unexpected forum origin" unless manifest["forum_origin"] == Discourse.base_url
slug = manifest.fetch("category_slug")
raise "invalid category slug" unless slug.match?(/\A[a-z][a-z0-9-]*\z/)
games = manifest.fetch("games")
unless games.is_a?(Array) && games.any? &&
         games.map { |game| game.fetch("id") }.uniq.size == games.size
  raise "invalid game list"
end
actor = Discourse.system_user
marker = "blackroom_games_release"
state = { category_id: nil, topic_ids: {} }

ActiveRecord::Base.transaction do
  category = Category.find_by(slug: slug)
  if category
    unless category.custom_fields[marker] == "1" && category.user_id == actor.id
      raise "existing category is not managed by this release"
    end
  else
    raise "category name already exists" if Category.exists?(name: "游戏")
    category =
      CategoryCreator.create(
        actor.guardian,
        name: "游戏",
        slug: slug,
        color: "5B65ED",
        text_color: "FFFFFF",
        permissions: {
          "trust_level_0" => :create_post,
          "staff" => :full,
        },
      )
    raise "category creation failed" unless category.persisted? && category.errors.empty?
    category.custom_fields[marker] = "1"
    category.save_custom_fields
  end
  expected = {
    Group::AUTO_GROUPS[:trust_level_0] => CategoryGroup.permission_types[:create_post],
    Group::AUTO_GROUPS[:staff] => CategoryGroup.permission_types[:full],
  }
  unless category.read_restricted &&
           category.category_groups.pluck(:group_id, :permission_type).to_h == expected
    raise "category permissions differ"
  end
  state[:category_id] = category.id
  games.each do |game|
    id = game.fetch("id")
    raise "invalid game id" unless id.match?(/\A[a-z][a-z0-9-]*\z/)
    title = "#{game.fetch("title")} · 游戏说明与朋友联机讨论"
    managed =
      Topic
        .joins(:_custom_fields)
        .where(category_id: category.id, topic_custom_fields: { name: marker, value: id })
        .to_a
    raise "duplicate managed game topics" if managed.size > 1
    topic = managed.first || Topic.find_by(category_id: category.id, title: title)
    if topic
      unless topic.user_id == actor.id && topic.custom_fields[marker] == id &&
               topic.deleted_at.nil? && topic.archetype == Archetype.default
        raise "existing topic is not managed by this release"
      end
    else
      post =
        PostCreator.create!(
          actor,
          title: title,
          category: category.id,
          tags: ["使用指南"],
          raw:
            "#{game.fetch("description")}\n\n仅向正常登录成员开放，使用桌面电脑操作。点击上方「在新页面开始游戏」进入，论坛页面会保留。\n\n打开游戏后可创建房间，或使用朋友提供的房间码、邀请链接加入指定房间。邀请链接不能代替成员登录。\n\n关闭游戏页面即可退出；在此回复交流玩法或反馈问题。",
        )
      topic = post.topic
      topic.custom_fields[marker] = id
      topic.save_custom_fields
    end
    state[:topic_ids][id] = topic.id
  end
  if ENV["BLACKROOM_GAMES_SHOW_SIDEBAR"] == "1"
    section = SidebarSection.find_by!(section_type: :community)
    raise "community section is not public" unless section.public && section.user_id == actor.id
    matches = section.sidebar_urls.where(name: "游戏").to_a
    raise "duplicate game sidebar links" if matches.size > 1
    if matches.any?
      raise "existing sidebar target differs" unless matches.first.value == category.url
    else
      url = SidebarUrl.create!(name: "游戏", value: category.url, icon: "gamepad", segment: :primary)
      section.sidebar_section_links.create!(linkable: url)
    end
  end
end
I18n.available_locales.each { |locale| I18n.with_locale(locale) { Site.clear_cache } }
puts JSON.generate(state)
