# frozen_string_literal: true

require "json"
require "tmpdir"
ARGV << "--load-only"
load File.join(__dir__, "blackroom_updates_bot.rb")

def check(condition, message)
  raise message unless condition
end

manifest = {
  "release_id" => "self-check",
  "announcement_title" => "站点更新｜2026-10-09｜验收更新助手",
  "announcement_raw" => "这是事务内验收公告，不对外发布。我们检查发布重试和教程的稳定地址。",
  "online_verified" => true,
  "guides" => [
    {
      "key" => "self-check-guide",
      "title" => "使用指南｜验收更新助手",
      "raw" => "这是事务内的教程正文，用于验证失败重试不会产生重复文章，教程更新保留已有回复。",
    },
  ],
}
BlackroomUpdatesBot.validate(manifest)
[
  { "online_verified" => false },
  { "release_id" => "../bad" },
  { "guides" => [] },
  { "guides" => manifest["guides"] * 2 },
  { "announcement_title" => "bad" },
  { "guides" => [manifest["guides"].first.merge("raw" => "")] },
].each do |change|
  begin
    BlackroomUpdatesBot.validate(manifest.merge(change))
  rescue StandardError
    next
  end
  raise "Invalid input accepted: #{change.keys}"
end
Dir.mktmpdir("blackroom-updates-check") do |directory|
  lock_path = File.join(directory, "publisher.lock")
  BlackroomUpdatesBot.with_lock(lock_path) do
    refused = false
    begin
      BlackroomUpdatesBot.with_lock(lock_path) { raise "Concurrent publisher entered" }
    rescue StandardError => error
      refused = error.message == "Another publisher is running"
    end
    check(refused, "Concurrent publication was not blocked")
  end
end
puts JSON.generate(input_validation: true, concurrent_lock: true)
exit unless defined?(Rails)

# Transactional probes suppress external jobs; no test topics or notifications survive.
PostCreator.prepend(
  Module.new do
    def initialize(user, opts)
      super(user, opts.merge(skip_jobs: true, skip_rate_limits: true))
    end

    def store_unique_post_key
      # Redis is outside the database rollback; probes must not leave duplicate-body keys.
    end
  end,
)
nonce = SecureRandom.hex(8)
manifest["announcement_raw"] += "\n\n验收编号：#{nonce}"
manifest["guides"][0]["raw"] += "\n\n验收编号：#{nonce}"
scheduled = []
Jobs.singleton_class.prepend(
  Module.new do
    define_method(:enqueue_at) do |time, job, args|
      if Thread.current[:updates_fail_pin] && job == :unpin_topic
        Thread.current[:updates_fail_pin] = false
        raise "Injected pin failure"
      end
      scheduled << [time, job, args]
    end
    define_method(:cancel_scheduled_job) { |*args| nil }
  end,
)
BlackroomUpdatesBot.singleton_class.prepend(
  Module.new do
    def create_post(bot, title, raw, fields)
      if Thread.current[:updates_fail_announcement] && fields.key?("release_id")
        Thread.current[:updates_fail_announcement] = false
        raise "Injected announcement failure"
      end
      super
    end
  end,
)

bot = User.find_by!(username: BlackroomUpdatesBot::USERNAME)
category = Category.find(2)
check(bot.id == -2, "Unexpected publishing identity")
baseline = Topic.where(user_id: bot.id).count
permission_matrix = []
Post.transaction do
  ["blackbox_animation", "blacklight_lit", nil].each do |group_name|
    username = "updates_#{SecureRandom.hex(5)}"
    user_id =
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
    user = User.find(user_id)
    user.send(:ensure_in_trust_level_group)
    GroupUser.create!(group: Group.find_by!(name: group_name), user: user) if group_name
    check(
      user.guardian.can_see_category?(category) &&
        user.guardian.can_create_topic_on_category?(category) &&
        user.guardian.can_post_in_category?(category),
      "Feedback member permissions failed",
    )
    private_access =
      Category
        .where(id: [38, 39, 45])
        .map { |item| [item.id, user.guardian.can_see_category?(item)] }
        .to_h
    check(
      private_access ==
        {
          38 => group_name == "blackbox_animation",
          39 => group_name == "blacklight_lit",
          45 => group_name == "blackbox_animation",
        },
      "Club isolation changed",
    )
    permission_matrix << {
      role: group_name || "non-member",
      feedback: true,
      private_access: private_access,
    }
  end
  admin = User.where(admin: true, active: true).where("id > 0").order(:id).first!
  check(admin.guardian.can_create_topic_on_category?(category), "Admin lost access")
  Dir.mktmpdir("updates-live-check") do |directory|
    path = File.join(directory, "release.json")
    File.write(path, JSON.generate(manifest))
    if (member_category = Category.find_by(slug: "podcasts"))
      check(bot.guardian.can_see_category?(member_category), "Bot lost ordinary member access")
    end
    BlackroomUpdatesBot.run(path)
    check(Topic.where(user_id: bot.id).count == baseline, "Preview wrote topics")
    Thread.current[:updates_fail_announcement] = true
    begin
      BlackroomUpdatesBot.run(path, publish: true)
    rescue StandardError => error
      raise unless error.message == "Injected announcement failure"
    end
    guide = BlackroomUpdatesBot.find_post(bot, "guide_key", "self-check-guide")
    check(
      guide && Topic.where(user_id: bot.id).count == baseline + 1,
      "Partial release did not preserve guide",
    )
    Thread.current[:updates_fail_pin] = true
    begin
      BlackroomUpdatesBot.run(path, publish: true)
    rescue StandardError => error
      raise unless error.message == "Injected pin failure"
    end
    check(
      Topic.where(user_id: bot.id).count == baseline + 2,
      "Pin failure lost announcement or duplicated guide",
    )
    BlackroomUpdatesBot.run(path, publish: true)
    announcement = BlackroomUpdatesBot.find_post(bot, "release_id", "self-check")
    check(
      announcement.topic.pinned_globally &&
        scheduled.any? do |entry|
          entry[1] == :unpin_topic && entry[2][:topic_id] == announcement.topic_id
        end,
      "Pin or expiry job missing",
    )
    check(guide.topic.reload.tags.exists?(name: "使用指南"), "Guide tag missing")
    check(announcement.topic.reload.tags.exists?(name: "功能更新"), "Announcement tag missing")
    extra_tag = Tag.find_by!(name: "使用指南")
    announcement.topic.tags << extra_tag
    tags_before = announcement.topic.tags.pluck(:name).sort
    tag_version = announcement.reload.version
    BlackroomUpdatesBot.ensure_tag(announcement, admin, "功能更新")
    check(
      announcement.reload.version == tag_version &&
        announcement.topic.reload.tags.pluck(:name).sort == tags_before,
      "Tag sync changed existing tags or repeated edits",
    )
    versions = guide.reload.version
    BlackroomUpdatesBot.run(path, publish: true)
    check(
      Topic.where(user_id: bot.id).count == baseline + 2 && guide.reload.version == versions,
      "Retry duplicated content",
    )
    reply =
      PostCreator.create(bot, topic_id: guide.topic_id, raw: "事务内的教程回复，用于验证更新正文不会删除已有讨论。#{nonce}")
    check(reply.persisted?, "Reply check failed")
    manifest["release_id"] = "self-check-next"
    manifest["announcement_title"] = "站点更新｜2026-10-09｜验收教程修订"
    manifest["announcement_raw"] = "教程新增操作说明，帮助成员找到更新后的使用方式。原来的地址继续使用，讨论和回复全部保留。"
    manifest["guides"][0]["raw"] += "\n\n这是新版本增加的步骤说明。"
    File.write(path, JSON.generate(manifest))
    BlackroomUpdatesBot.run(path, publish: true)
    check(
      BlackroomUpdatesBot.find_post(bot, "guide_key", "self-check-guide").id == guide.id &&
        Post.exists?(reply.id),
      "Guide URL or replies lost",
    )
    check(!announcement.topic.reload.pinned_at, "Previous managed announcement still pinned")
    Topic.where(id: guide.topic_id).update_all(deleted_at: Time.current)
    begin
      BlackroomUpdatesBot.find_post(bot, "guide_key", "self-check-guide")
      raise "Deleted publication accepted"
    rescue StandardError => error
      raise unless error.message.start_with?("Publication was removed")
    end
  end
  raise ActiveRecord::Rollback
end
check(Topic.where(user_id: bot.id).count == baseline, "Test topics survived rollback")
puts JSON.generate(
       permissions: permission_matrix,
       admin_access: true,
       publishing_identity: bot.username,
       preview_read_only: true,
       partial_retry: true,
       pin_retry: true,
       deduplication: true,
       guide_revision_preserves_replies: true,
       expiry_scheduled: true,
       soft_deleted_blocked: true,
       rolled_back: true,
     )
