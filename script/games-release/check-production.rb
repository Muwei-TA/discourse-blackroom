# frozen_string_literal: true

raise "games plugin is not loaded" unless defined?(BlackRoomGames::GamesController)
config = BlackRoomGames.config
raise "unexpected forum origin" unless config.fetch("forum_origin") == Discourse.base_url
path = ENV.fetch("BLACKROOM_GAMES_CONFIG", "/shared/state/blackroom-games/forum.json")
raise "configuration is not private" if (File.stat(path).mode & 0o077).nonzero?
category = Category.find(config.fetch("category_id"))
expected = {
  Group::AUTO_GROUPS[:trust_level_0] => CategoryGroup.permission_types[:create_post],
  Group::AUTO_GROUPS[:staff] => CategoryGroup.permission_types[:full],
}
unless category.read_restricted &&
         category.category_groups.pluck(:group_id, :permission_type).to_h == expected
  raise "category permissions differ"
end
raise "anonymous category access" if Guardian.new.can_see_category?(category)
unless category.custom_fields["blackroom_games_release"] == "1" &&
         category.user_id == Discourse.system_user.id
  raise "missing release ownership"
end
state = { category_id: category.id, topic_ids: {} }
config
  .fetch("games")
  .each do |game|
    topic = Topic.find(game.fetch("topic_id"))
    unless topic.category_id == category.id && topic.deleted_at.nil? &&
             topic.archetype == Archetype.default
      raise "invalid game topic"
    end
    unless topic.custom_fields["blackroom_games_release"] == game.fetch("id") &&
             topic.user_id == Discourse.system_user.id
      raise "missing topic ownership"
    end
    raise "anonymous topic access" if Guardian.new.can_see?(topic)
    raise "system cannot access game topic" unless Discourse.system_user.guardian.can_see?(topic)
    state[:topic_ids][game.fetch("id")] = topic.id
  end
raise "empty game catalog" if state[:topic_ids].empty?
puts({ ok: true, forum_state: state, anonymous_denied: true, config_private: true }.to_json)
