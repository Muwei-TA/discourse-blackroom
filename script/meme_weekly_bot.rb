# frozen_string_literal: true

require "json"
require "date"
require "uri"
require "digest"
require_relative "blackroom_bot_tags"

module MemeWeeklyBot
  extend BlackroomBotTags
  TAG = "哪来的傻缺图"
  def self.validate(manifest, root:, seen: [], test: false)
    date = Date.iso8601(manifest.fetch("date"))
    raise "Issue date must be Friday" unless date.friday? || test
    items = manifest.fetch("items")
    count_range = test ? (4..18) : (12..18)
    unless items.is_a?(Array) && count_range.cover?(items.size)
      raise "Expected #{count_range} selected images"
    end
    hashes = []
    sources = []
    items.each do |item|
      raise "Image was not reviewed" unless item.fetch("reviewed") == true
      %w[author reason rights_basis].each do |field|
        value = item.fetch(field)
        unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
          raise "Missing #{field}"
        end
      end
      url = URI(item.fetch("source_url"))
      unless url.is_a?(URI::HTTPS) && url.host && !url.userinfo && !url.to_s.match?(/[\s<>]/)
        raise "Invalid source URL"
      end
      if item.key?("license_url") || item.key?("license")
        license = item.fetch("license")
        unless license.is_a?(String) && !license.strip.empty? && !license.match?(/[\r\n]/)
          raise "Invalid license name"
        end
        license_url = URI(item.fetch("license_url"))
        unless license_url.is_a?(URI::HTTPS) && license_url.host == "creativecommons.org" &&
                 !license_url.userinfo && !license_url.to_s.match?(/[\s<>]/)
          raise "Invalid license URL"
        end
      end
      path = File.realpath(File.join(root, item.fetch("file")))
      raise "Image outside issue directory" unless path.start_with?(File.realpath(root) + "/")
      raise "Image too large" unless File.size(path).between?(1, 10 * 1024 * 1024)
      hash = Digest::SHA1.file(path).hexdigest
      raise "Previously published image" if seen.include?(hash) || seen.include?(url.to_s)
      hashes << hash
      sources << url.to_s
      item["path"] = path
    end
    unless hashes.uniq.size == items.size && sources.uniq.size == items.size
      raise "Duplicate image or source"
    end
    { date: date, items: items, hashes: hashes, sources: sources }
  end

  def self.run(path, publish: false, test: false)
    raise "Unexpected site" unless Discourse.base_url == "https://discourse.muwei.xyz"
    bot = User.find_by!(username: "discobot")
    category = Category.find_by!(slug: "image-gallery")
    raise "Unexpected publishing identity" unless bot.id == -2
    raise "Bot cannot publish" unless bot.guardian.can_create_topic_on_category?(category)
    manifest = JSON.parse(File.read(path))
    date = Date.iso8601(manifest.fetch("date"))
    issues =
      Topic
        .with_deleted
        .where(user_id: bot.id, category_id: category.id)
        .where("title LIKE ?", "哪来的傻缺图｜%")
    existing = issues.find_by("title LIKE ?", "%｜#{date}")
    if existing
      if publish
        if existing.deleted_at || !existing.visible
          raise "Publication was removed; review it before retrying"
        end
        editor = User.where(admin: true, active: true).where("id > 0").order(:id).first!
        ensure_tag(existing.first_post, editor, TAG)
      end
      puts({ status: "already_published", topic_id: existing.id, url: existing.url }.to_json)
      return
    end
    today = Time.current.in_time_zone("Asia/Shanghai").to_date
    raise "Publish only on this issue's date" if publish && date != today
    seen =
      PostCustomField
        .where(
          post_id: Post.where(topic_id: issues.select(:id)).select(:id),
          name: "meme_weekly_sources",
        )
        .pluck(:value)
        .flat_map { |value| JSON.parse(value) }
    issue = validate(manifest, root: File.dirname(path), seen: seen, test: test)
    issue[:items].each do |item|
      info = FastImage.new(item.fetch("path"))
      raise "Unsupported image" unless %i[jpeg png gif webp].include?(info.type) && info.size
    end
    number = issues.where("title LIKE ?", "哪来的傻缺图｜第%期｜%").count + 1
    title = "哪来的傻缺图｜#{test ? "试刊" : "第#{number}期"}｜#{date}"
    unless publish
      puts(
        {
          status: "preview_validated",
          title: title,
          count: issue[:items].size,
          authors: issue[:items].map { |item| item.fetch("author") },
        }.to_json,
      )
      return
    end
    raw =
      issue[:items]
        .map do |item|
          upload =
            File.open(item.fetch("path"), "rb") do |file|
              UploadCreator.new(file, File.basename(item.fetch("path"))).create_for(bot.id)
            end
          unless upload.persisted? && upload.errors.empty?
            raise upload.errors.full_messages.join("; ")
          end
          if FastImage.animated?(item.fetch("path")) && !upload.animated?
            raise "Animation lost during upload"
          end
          author = item.fetch("author").gsub(/[\\\[\]`*_<>|]/) { |char| "\\#{char}" }
          source = item.fetch("source_url").gsub(/[()]/) { |char| "%%%02X" % char.ord }
          credit = "作者：[#{author}](#{source})"
          if item["license_url"]
            license = item.fetch("license").gsub(/[\\\[\]`*_<>|]/) { |char| "\\#{char}" }
            license_url = item.fetch("license_url").gsub(/[()]/) { |char| "%%%02X" % char.ord }
            credit += " · [#{license}](#{license_url})"
          end
          "#{UploadMarkdown.new(upload).image_markdown(display_name: "作品")}\n\n#{credit}"
        end
        .join("\n\n---\n\n")
    ActiveRecord::Base.transaction(requires_new: true) do
      creator = PostCreator.new(bot, title: title, raw: raw, category: category.id)
      post = creator.create
      raise creator.errors.full_messages.join("; ") unless post&.persisted? && creator.errors.empty?
      editor = User.where(admin: true, active: true).where("id > 0").order(:id).first!
      ensure_tag(post, editor, TAG)
      post.custom_fields["meme_weekly_sources"] = JSON.generate(issue[:hashes] + issue[:sources])
      post.save_custom_fields
      puts(
        {
          status: "published",
          topic_id: post.topic_id,
          url: post.topic.url,
          count: issue[:items].size,
        }.to_json,
      )
    end
  end
end

if defined?(Rails) && !ARGV.delete("--load-only")
  File.open("/shared/state/meme-weekly.lock", File::RDWR | File::CREAT, 0o600) do |lock|
    raise "Another publisher is running" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    publish = ARGV.delete("--publish")
    test = ARGV.delete("--test")
    MemeWeeklyBot.run(ARGV.fetch(0), publish: publish, test: test)
  end
end
