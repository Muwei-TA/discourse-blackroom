require "json"

raise "unexpected production site" unless Discourse.base_url == "https://discourse.muwei.xyz"
actor = User.find(-2)
raise "unexpected publisher" unless actor.username == "discobot" && actor.admin?
category = Category.find(53)
raise "unexpected game category" unless category.slug == "games" && category.read_restricted
expected = {
  Group::AUTO_GROUPS[:trust_level_0] => CategoryGroup.permission_types[:create_post],
  Group::AUTO_GROUPS[:staff] => CategoryGroup.permission_types[:full],
}
raise "game permissions changed" unless category.category_groups.pluck(:group_id, :permission_type).to_h == expected
marker = "blackroom_games_release"
matches = Topic.joins(:_custom_fields).where(category_id: category.id, topic_custom_fields: {name: marker, value: "freeboardgames"}).to_a
raise "duplicate registration" if matches.size > 1
topic = matches.first
if topic
  raise "registration ownership mismatch" unless topic.user_id == actor.id && topic.deleted_at.nil?
else
  title = "黑房桌游 · 游戏说明与朋友联机讨论"
  raise "unmanaged topic already exists" if Topic.exists?(category_id: category.id, title: title)
  raw = <<~MD
    黑房桌游使用 FreeBoardGames，提供井字棋、国际象棋、黑白棋等多人桌面浏览器游戏。仅正常登录且可以访问游戏板块的成员可玩。

    从[游戏板块](/c/games/53)点击黑房桌游「进入游戏」，在新标签页打开。选择喜欢的游戏，再选择 Online Friend／在线朋友和人数创建房间。打开首页不会自动加入已有房间。

    昵称默认当前本站用户名，可在房间成员名单旁手动修改。支持中文与 emoji，最多 32 个 Unicode 字符，不改变论坛资料；刷新重新默认本站用户名。

    用房间的邀请按钮复制链接发给朋友，朋友登录后进入同一间房。人数够后由创建者点击 Start Match／开始对局。邀请不能代替成员认证；房间和游戏规则由桌游程序管理。

    退出浏览器后重新打开首页不会自动加入他人的房间。部分房间和对局状态存储在独立数据库，服务恢复能力与游戏本身有关；不要把它当成永久云存档。

    本次接入验证以井字棋为代表，不保证每款游戏都已逐项验收。反馈请在此回复，附游戏名、浏览器和操作步骤。

    [对应版本源码与许可](https://boardgames.muwei.xyz/source.tar.gz)（AGPL-3.0-or-later；经本站成员门禁提供）。
  MD
  post = PostCreator.create!(actor, title: title, raw: raw, category: category.id, tags: ["使用指南"])
  topic = post.topic
  topic.custom_fields[marker] = "freeboardgames"
  topic.save_custom_fields
end
puts JSON.generate({category_id: category.id, topic_id: topic.id, author: actor.username})
