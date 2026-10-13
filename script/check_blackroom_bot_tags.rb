# frozen_string_literal: true

require "tmpdir"
require "base64"
%w[acg_daily_bot meme_weekly_bot blackroom_updates_bot].each do |name|
  ARGV << "--load-only"
  load File.join(__dir__, "#{name}.rb")
end

PostCreator.prepend(
  Module.new do
    def initialize(user, opts)
      super(user, opts.merge(skip_jobs: true, skip_rate_limits: true))
    end

    def store_unique_post_key
    end
  end,
)
nonce = SecureRandom.hex(8)
AcgDailyBot.define_singleton_method(:collect_sections) do |**_args|
  { "验收" => [{ title: "游戏发布 #{nonce}", url: "https://www.gcores.com/#{nonce}", source: "机核" }] }
end
AcgDailyBot.singleton_class.prepend(
  Module.new do
    def ensure_tag(post, editor, tag)
      raise "Injected tagging failure" if Thread.current[:bot_tags_fail]
      super
    end
  end,
)
upload = Upload.find(55)
UploadCreator.prepend(Module.new { define_method(:create_for) { |_user_id| upload } })
admin = User.where(admin: true, active: true).where("id > 0").order(:id).first!
baseline = Topic.count
ActiveRecord::Base.transaction do
  date = Time.current.in_time_zone("Asia/Shanghai").to_date
  daily = User.find_by!(username: "discobot")
  Topic.where(user_id: daily.id, title: "ACG 日报｜#{date}").update_all(title: "验收前日报 #{nonce}")
  before = Topic.count
  Thread.current[:bot_tags_fail] = true
  begin
    AcgDailyBot.run(publish: true)
    raise "Tagging failure accepted"
  rescue StandardError => error
    raise unless error.message == "Injected tagging failure"
  ensure
    Thread.current[:bot_tags_fail] = false
  end
  raise "Untagged topic survived failure" unless Topic.count == before
  AcgDailyBot.run(publish: true)
  topic = Topic.find_by!(user_id: daily.id, title: "ACG 日报｜#{date}")
  raise "Daily tag missing" unless topic.tags.exists?(name: AcgDailyBot::TAG)
  extra = Tag.find_by!(name: "动画影像")
  topic.tags << extra
  topic.tags.delete(Tag.find_by!(name: AcgDailyBot::TAG))
  raw = topic.first_post.raw
  bumped = topic.bumped_at
  AcgDailyBot.run
  raise "Preview modified tags" if topic.reload.tags.exists?(name: AcgDailyBot::TAG)
  AcgDailyBot.run(publish: true)
  unless topic.reload.tags.pluck(:name).sort == [AcgDailyBot::TAG, extra.name].sort
    raise "Daily tag repair failed"
  end
  version = topic.first_post.reload.version
  AcgDailyBot.run(publish: true)
  unless Topic.count == before + 1 && topic.first_post.reload.version == version &&
           topic.first_post.raw == raw && topic.reload.bumped_at == bumped
    raise "Daily duplicate or content change"
  end

  Dir.mktmpdir do |root|
    items =
      4.times.map do |index|
        File.binwrite(
          File.join(root, "#{index}.png"),
          Base64.decode64(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aipkAAAAASUVORK5CYII=",
          ) + "#{nonce}#{index}",
        )
        {
          "file" => "#{index}.png",
          "source_url" => "https://example.com/#{nonce}/#{index}",
          "author" => "事务验收",
          "reviewed" => true,
          "reason" => "测试",
          "rights_basis" => "测试样本",
        }
      end
    path = File.join(root, "manifest.json")
    File.write(path, JSON.generate(date: date.to_s, items: items))
    MemeWeeklyBot.run(path, publish: true, test: true)
    meme =
      Topic.find_by!(user_id: User.find_by!(username: "discobot").id, title: "哪来的傻缺图｜试刊｜#{date}")
    raise "Meme tag missing" unless meme.tags.exists?(name: MemeWeeklyBot::TAG)
    meme.tags << extra
    meme.tags.delete(Tag.find_by!(name: MemeWeeklyBot::TAG))
    bumped = meme.bumped_at
    raw = meme.first_post.raw
    MemeWeeklyBot.run(path, test: true)
    raise "Meme preview modified tags" if meme.reload.tags.exists?(name: MemeWeeklyBot::TAG)
    MemeWeeklyBot.run(path, publish: true, test: true)
    unless meme.reload.tags.pluck(:name).sort == [MemeWeeklyBot::TAG, extra.name].sort
      raise "Meme tag repair failed"
    end
    version = meme.first_post.reload.version
    MemeWeeklyBot.run(path, publish: true, test: true)
    unless Topic.count == before + 2 && meme.first_post.reload.version == version &&
             meme.first_post.raw == raw && meme.reload.bumped_at == bumped
      raise "Meme duplicate or content change"
    end
    meme.update!(deleted_at: Time.current)
    begin
      MemeWeeklyBot.run(path, publish: true, test: true)
      raise "Removed publication accepted"
    rescue StandardError => error
      raise unless error.message == "Publication was removed; review it before retrying"
    end
  end
  raise ActiveRecord::Rollback
end
raise "Test topics survived rollback" unless Topic.count == baseline
puts JSON.generate(
       new_topics_tagged: true,
       failed_tagging_rolled_back: true,
       retries_repair_tags: true,
       previews_read_only: true,
       existing_tags_preserved: true,
       content_and_bump_preserved: true,
       removed_publication_blocked: true,
       test_topics_rolled_back: true,
     )
