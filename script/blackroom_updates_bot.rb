# frozen_string_literal: true

require "json"
require "digest"
require_relative "blackroom_bot_tags"

module BlackroomUpdatesBot
  extend BlackroomBotTags
  USERNAME = "discobot"
  CATEGORY_ID = 2
  PREFIX = "blackroom_updates_"

  def self.validate(manifest)
    raise "Expected an object" unless manifest.is_a?(Hash)
    %w[release_id announcement_title announcement_raw].each do |key|
      raise "Missing #{key}" unless manifest[key].is_a?(String) && !manifest[key].strip.empty?
    end
    raise "Invalid release ID" unless manifest["release_id"].match?(/\A[a-z0-9][a-z0-9_-]{0,79}\z/)
    unless manifest["announcement_title"].match?(/\A站点更新｜\d{4}-\d{2}-\d{2}｜[^\r\n]+\z/)
      raise "Invalid announcement title"
    end
    raise "Online verification required" unless manifest["online_verified"] == true
    guides = manifest.fetch("guides")
    raise "Expected at least one guide" unless guides.is_a?(Array) && !guides.empty?
    guides.each do |guide|
      raise "Invalid guide" unless guide.is_a?(Hash)
      unless guide["key"].is_a?(String) && guide["key"].match?(/\A[a-z0-9][a-z0-9_-]{0,79}\z/)
        raise "Invalid guide key"
      end
      unless guide["title"].is_a?(String) && guide["title"].match?(/\A使用指南｜[^\r\n]+\z/)
        raise "Invalid guide title"
      end
      raise "Missing guide body" unless guide["raw"].is_a?(String) && !guide["raw"].strip.empty?
    end
    raise "Duplicate guide keys" unless guides.map { |guide| guide["key"] }.uniq.size == guides.size
    manifest
  end

  def self.find_post(bot, field, value)
    posts =
      Post
        .with_deleted
        .where(user_id: bot.id, post_number: 1)
        .joins(:_custom_fields)
        .where(post_custom_fields: { name: PREFIX + field, value: value })
        .to_a
    raise "Duplicate publication records" if posts.size > 1
    post = posts.first
    topic = Topic.with_deleted.find(post.topic_id) if post
    if post &&
         (
           post.deleted_at || topic.deleted_at || !topic.visible ||
             topic.category_id != CATEGORY_ID || topic.archetype != Archetype.default
         )
      raise "Publication was removed; restore or review it before retrying"
    end
    post
  end

  def self.create_post(bot, title, raw, fields)
    # A verified release publishes several guides together without changing site-wide limits.
    creator =
      PostCreator.new(
        bot,
        title: title,
        raw: raw,
        category: CATEGORY_ID,
        skip_rate_limits: true,
        custom_fields: fields.transform_keys { |key| PREFIX + key },
      )
    ActiveRecord::Base.transaction(requires_new: true) do
      post = creator.create
      raise creator.errors.full_messages.join("; ") unless post&.persisted? && creator.errors.empty?
      editor = User.where(admin: true, active: true).where("id > 0").order(:id).first!
      ensure_tag(post, editor, fields.key?("release_id") ? "功能更新" : "使用指南")
      post
    end
  end

  def self.revise(post, editor, title, raw)
    ensure_tag(post, editor, "使用指南")
    return if post.raw == raw && post.topic.title == title
    raise "Cannot edit managed guide" unless editor.guardian.can_edit_post?(post)
    revisor = PostRevisor.new(post)
    revised =
      revisor.revise!(editor, { title: title, raw: raw }, expected_raw: post.raw, bypass_bump: true)
    raise "Guide revision failed: #{post.errors.full_messages.join("; ")}" unless revised
  end

  def self.run(path, publish: false)
    raise "Unexpected site" unless Discourse.base_url == "https://discourse.muwei.xyz"
    manifest = validate(JSON.parse(File.read(path)))
    bot = User.find_by!(username: USERNAME)
    category = Category.find(CATEGORY_ID)
    raise "Unexpected category" unless category.name == "网站反馈"
    raise "Unexpected publishing identity" unless bot.id == -2
    raise "Unexpected private publishing target" if category.read_restricted
    raise "Bot cannot publish" unless bot.guardian.can_create_topic_on_category?(category)
    admin = User.where(admin: true, active: true).where("id > 0").order(:id).first!
    release_id = manifest.fetch("release_id")
    digest = Digest::SHA256.hexdigest(JSON.generate(manifest))
    announcement = find_post(bot, "release_id", release_id)
    if announcement && announcement.custom_fields[PREFIX + "digest"] != digest
      raise "Release ID already used with different content"
    end
    guides =
      manifest
        .fetch("guides")
        .map { |guide| [guide, find_post(bot, "guide_key", guide.fetch("key"))] }
    unless publish
      puts JSON.generate(
             status: "preview",
             release_id: release_id,
             announcement: manifest["announcement_title"],
             raw: manifest["announcement_raw"],
             guides:
               guides.map do |guide, post|
                 guide.merge("action" => post ? "update" : "create", "url" => post&.topic&.url)
               end,
           )
      return
    end
    raise "Publisher is disabled" if File.exist?("/shared/state/blackroom-updates.disabled")
    if announcement&.custom_fields&.fetch(PREFIX + "completed", nil) == "true"
      ensure_tag(announcement, admin, "功能更新")
      guides.each { |_, post| ensure_tag(post, admin, "使用指南") if post }
      puts JSON.generate(
             status: "already_published",
             topic_id: announcement.topic_id,
             url: announcement.topic.url,
           )
      return
    end
    unless announcement
      managed_announcements =
        Post
          .where(user_id: bot.id, post_number: 1)
          .joins(:_custom_fields)
          .where(post_custom_fields: { name: PREFIX + "release_id" })
      if managed_announcements.any? { |post| post.custom_fields[PREFIX + "completed"] != "true" }
        raise "Finish the previous incomplete release first"
      end
      guides =
        guides.map do |guide, post|
          if post
            revise(post, admin, guide.fetch("title"), guide.fetch("raw"))
          else
            post =
              create_post(
                bot,
                guide.fetch("title"),
                guide.fetch("raw"),
                "guide_key" => guide.fetch("key"),
              )
          end
          [guide, post]
        end
      links =
        guides.map { |guide, post| "- [#{guide.fetch("title")}](#{post.topic.url})" }.join("\n")
      raw =
        manifest.fetch("announcement_raw") + "\n\n## 使用教程\n\n" + links +
          "\n\n已有教程会随本次更新同步修订。使用时遇到问题，欢迎在本帖回复。"
      announcement =
        create_post(
          bot,
          manifest.fetch("announcement_title"),
          raw,
          "release_id" => release_id,
          "digest" => digest,
        )
    end
    guides.each do |guide, post|
      raise "Managed guide missing" unless post
      raw =
        guide.fetch("raw") +
          "\n\n---\n\n相关更新：[#{manifest.fetch("announcement_title")}](#{announcement.topic.url})"
      revise(post, admin, guide.fetch("title"), raw)
    end
    topic = announcement.topic
    raise "Admin cannot pin announcement" unless admin.guardian.can_pin_unpin_topic?(topic)
    deadline = (topic.created_at + 7.days).iso8601
    if topic.created_at + 7.days > Time.current &&
         (!topic.pinned_globally || topic.pinned_until&.iso8601 != deadline)
      topic.update_status("pinned_globally", true, admin, until: deadline)
    end
    previous =
      Topic
        .where(user_id: bot.id, category_id: CATEGORY_ID)
        .where.not(id: topic.id)
        .joins(posts: :_custom_fields)
        .where(posts: { post_number: 1 }, post_custom_fields: { name: PREFIX + "release_id" })
        .distinct
    previous
      .where.not(pinned_at: nil)
      .each { |old| old.update_status("pinned_globally", false, admin) }
    announcement.custom_fields[PREFIX + "completed"] = "true"
    announcement.save_custom_fields
    puts JSON.generate(
           status: "published",
           topic_id: topic.id,
           url: topic.url,
           pinned_until: topic.reload.pinned_until,
           guides:
             guides.map do |guide, post|
               { key: guide["key"], topic_id: post.topic_id, url: post.topic.url }
             end,
         )
  end

  def self.with_lock(path)
    File.open(path, File::RDWR | File::CREAT, 0o600) do |lock|
      raise "Another publisher is running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      yield
    end
  end
end

if defined?(Rails) && !ARGV.delete("--load-only")
  BlackroomUpdatesBot.with_lock("/shared/state/blackroom-updates.lock") do
    publish = ARGV.delete("--publish")
    BlackroomUpdatesBot.run(ARGV.fetch(0), publish: !!publish)
  end
end
