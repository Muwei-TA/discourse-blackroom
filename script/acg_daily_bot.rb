# frozen_string_literal: true

require "rss"
require "net/http"
require "cgi"
require "json"
require_relative "blackroom_bot_tags"

module AcgDailyBot
  extend BlackroomBotTags
  TAG = "acg日报"
  SOURCES = {
    "游戏与 ACG 资讯" => [
      %w[机核 https://www.gcores.com/rss www.gcores.com],
      ["Nintendo Life", "https://www.nintendolife.com/feeds/latest", "www.nintendolife.com"],
      %w[Eurogamer https://www.eurogamer.net/feed www.eurogamer.net],
    ],
    "新番资讯、预告与开播" => [
      [
        "Anime News Network",
        "https://www.animenewsnetwork.com/news/rss.xml?ann-edition=us",
        "www.animenewsnetwork.com",
      ],
      [
        "Crunchyroll News",
        "https://cr-news-api-service.prd.crunchyrollsvc.com/v1/en-US/rss",
        "crunchyroll.com",
      ],
    ],
  }.freeze
  ANIME_NEWS = /anime|trailer|premiere|debut|teaser|broadcast/i
  GAME_NEWS =
    /游戏|Xbox|Steam|PlayStation|Nintendo|Switch|预告|发售|上线|登陆|宣布|game|trailer|release|launch|console|patch|update/i
  EXCLUDED = /裸体|色情|成人|R18|NSFW|hentai|nude|nudity|X-rated|full-frontal|erotic/i

  def self.select_items(xml, host:, since:, now:, seen:, anime: false, gaming: false)
    feed = RSS::Parser.parse(xml, false)
    raise "Expected RSS items" unless feed.respond_to?(:items)
    feed
      .items
      .filter_map do |item|
        title = CGI.unescapeHTML(item.title.to_s).gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
        link = URI.parse(item.link.to_s)
        published = item.pubDate
        next unless link.scheme == "https" && link.host == host && !link.userinfo
        next unless published && published > since && published <= now
        next if title.empty? || title.match?(EXCLUDED) || seen.include?(link.to_s)
        next if anime && !title.match?(ANIME_NEWS)
        next if gaming && !title.match?(GAME_NEWS)
        seen.add(link.to_s)
        { title: title[0, 220], url: link.to_s, published: published }
      rescue URI::InvalidURIError
        nil
      end
      .sort_by { |item| item[:published] }
      .reverse
      .first(6)
  end

  def self.fetch(url)
    uri = URI(url)
    response =
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: 10,
        read_timeout: 20,
      ) do |http|
        http.get(
          uri.request_uri,
          {
            "User-Agent" => "BlackRoomDailyBot/1.0 (+https://discourse.muwei.xyz)",
            "Accept" => "application/rss+xml, application/xml",
          },
        )
      end
    raise "Feed HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    raise "Feed exceeds 2 MiB" if response.body.bytesize > 2 * 1024 * 1024
    response.body
  end

  def self.body(sections, translations: nil)
    cache = "/shared/state/acg-daily-translations.json"
    translations ||= File.exist?(cache) ? JSON.parse(File.read(cache)) : {}
    lines = ["每日整理游戏、ACG 与新番消息，供大家讨论。以下按发布时间选取，并非全网热度排名；标题与链接来自原站。", ""]
    sections.each do |heading, items|
      lines += ["## #{heading}", ""]
      if items.empty?
        lines << "本次抓取范围内暂无新的相关资讯。"
      else
        items.each do |item|
          translated = translations[item[:title]] unless item[:source] == "机核"
          title = (translated || item[:title]).gsub(/[\\\[\]`*_<>]/) { |char| "\\#{char}" }
          lines << "- [#{title}](#{item[:url].gsub(/[()\s]/) { |char| "%%%02X" % char.ord }}) — #{item.fetch(:source)}"
          if translated
            lines[-1] += "  "
            original = item[:title].gsub(/[\\\[\]`*_<>]/) { |char| "\\#{char}" }
            lines << "  原标题：#{original}"
          elsif item[:source] != "机核"
            lines << "  （翻译暂不可用，保留原文）"
          end
        end
      end
      lines << ""
    end
    lines << "海外标题提供中文译文并保留原文；自动翻译仅供参考。新番栏目包含当季及后续已公布作品的消息，播出安排以官方公告为准。欢迎在回复中补充介绍与讨论。"
    lines.join("\n")
  end

  def self.collect_sections(since:, now:, seen:)
    SOURCES.to_h do |heading, sources|
      items =
        sources.flat_map do |name, url, host|
          select_items(
            fetch(url),
            host: host,
            since: since,
            now: now,
            seen: seen,
            anime: heading.start_with?("新番"),
            gaming: heading.start_with?("游戏"),
          ).map { |item| item.merge(source: name) }
        end
      [heading, items.sort_by { |item| item[:published] }.reverse.first(6)]
    end
  end

  def self.run(publish: false, prepare_translations: false)
    raise "Unexpected site" unless Discourse.base_url == "https://discourse.muwei.xyz"
    now = Time.current
    date = now.in_time_zone("Asia/Shanghai").to_date
    title = "ACG 日报｜#{date}"
    category = Category.find_by!(slug: "acg-daily")
    bot = User.find_by!(username: "discobot")
    raise "Unexpected publishing identity" unless bot.id == -2
    raise "Bot cannot publish" unless bot.guardian.can_create_topic_on_category?(category)
    existing = Topic.find_by(category_id: category.id, user_id: bot.id, title: title)
    if existing
      if publish
        editor = User.where(admin: true, active: true).where("id > 0").order(:id).first!
        ensure_tag(existing.first_post, editor, TAG)
      end
      puts({ status: "already_published", topic_id: existing.id, url: existing.url }.to_json)
      return
    end

    recent =
      Post
        .where(user_id: bot.id, post_number: 1)
        .joins(:topic)
        .where(topics: { category_id: category.id })
        .order(created_at: :desc)
        .limit(7)
        .to_a
    since = [recent.first&.created_at || now - 24.hours, now - 72.hours].max
    seen = recent.flat_map { |post| post.raw.scan(%r{https://[^\s)]+}) }.to_set
    sections = collect_sections(since: since, now: now, seen: seen)
    if prepare_translations
      puts(
        {
          status: "translation_titles",
          titles:
            sections
              .values
              .flatten
              .reject { |item| item[:source] == "机核" }
              .map { |item| item[:title] }
              .uniq,
        }.to_json,
      )
      return
    end
    raw = body(sections)
    unless publish
      puts(
        {
          status: "preview",
          title: title,
          counts: sections.transform_values(&:size),
          raw: raw,
        }.to_json,
      )
      return
    end

    # ponytail: keyword filtering is not editorial review; add a moderation queue if unsuitable items appear.
    creator = PostCreator.new(bot, title: title, raw: raw, category: category.id)
    post =
      ActiveRecord::Base.transaction(requires_new: true) do
        created = creator.create
        unless created&.persisted? && creator.errors.empty?
          raise creator.errors.full_messages.join("; ")
        end
        editor = User.where(admin: true, active: true).where("id > 0").order(:id).first!
        ensure_tag(created, editor, TAG)
        created
      end
    puts(
      {
        status: "published",
        topic_id: post.topic_id,
        url: post.topic.url,
        counts: sections.transform_values(&:size),
      }.to_json,
    )
  end
end

if ARGV.delete("--self-test")
  now = Time.utc(2026, 10, 8, 4)
  entries = [
    ["TV Anime [Trailer]", "https://example.com/news/1", now - 60],
    ["Old Anime", "https://example.com/news/2", now - 90_000],
    ["Future Anime", "https://example.com/news/3", now + 60],
    ["Anime bad link", "https://evil.example/news/1", now - 60],
    ["Anime NSFW", "https://example.com/news/4", now - 60],
    ["Anime X-rated nudity", "https://example.com/news/6", now - 60],
    ["Manga news", "https://example.com/news/5", now - 60],
  ]
  xml =
    "<rss version='2.0'><channel><title>test</title><link>https://example.com</link><description>test</description>" +
      entries
        .map do |title, link, date|
          "<item><title>#{title}</title><link>#{link}</link><pubDate>#{date.rfc2822}</pubDate></item>"
        end
        .join + "</channel></rss>"
  seen = Set.new
  items =
    AcgDailyBot.select_items(
      xml,
      host: "example.com",
      since: now - 86_400,
      now: now,
      seen: seen,
      anime: true,
    )
  raise "Filtering failed" unless items.size == 1 && items.first[:title] == "TV Anime [Trailer]"
  mixed =
    AcgDailyBot.select_items(xml, host: "example.com", since: now - 86_400, now: now, seen: seen)
  raise "Deduplication failed" unless mixed.size == 1 && mixed.first[:title] == "Manga news"
  seen = Set["https://example.com/news/1"]
  unless AcgDailyBot.select_items(
           xml,
           host: "example.com",
           since: now - 86_400,
           now: now,
           seen: seen,
           anime: true,
         ).empty?
    raise "Seen article included"
  end
  if AcgDailyBot.body({ "游戏与 ACG 资讯" => items.map { |item| item.merge(source: "Test source") } })[
       "\\[Trailer\\]"
     ].nil?
    raise "Markdown escaping failed"
  end
  games =
    AcgDailyBot.select_items(
      xml.sub("TV Anime [Trailer]", "Unrelated essay").sub("Manga news", "游戏发售"),
      host: "example.com",
      since: now - 86_400,
      now: now,
      seen: Set.new,
      gaming: true,
    )
  raise "Gaming filter failed" unless games.size == 1 && games.first[:title] == "游戏发售"
  original_fetch = AcgDailyBot.method(:fetch)
  calls = []
  source_list = AcgDailyBot::SOURCES.values.flatten(1)
  AcgDailyBot.define_singleton_method(:fetch) do |url|
    calls << url
    index = source_list.index { |source| source[1] == url }
    host = source_list[index][2]
    xml.sub(
      "</channel>",
      (0...8)
        .map do |i|
          "<item><title>Anime game trailer #{i}</title><link>https://#{host}/news/#{i + 10}</link><pubDate>#{(now - 100 + index * 10 + i).rfc2822}</pubDate></item>"
        end
        .join + "</channel>",
    )
  end
  sections = AcgDailyBot.collect_sections(since: now - 86_400, now: now, seen: Set.new)
  AcgDailyBot.define_singleton_method(:fetch, original_fetch)
  raise "Not all sources fetched" unless calls == source_list.map { |source| source[1] }
  raise "Per-section cap failed" unless sections.values.all? { |selected| selected.size == 6 }
  unless sections.values.flatten.map { |item| item[:source] }.uniq.sort ==
           ["Crunchyroll News", "Eurogamer"]
    raise "Item source labels failed"
  end
  raise "Rendered source labels missing" if AcgDailyBot.body(sections)["— Crunchyroll News"].nil?
  example = {
    "新番资讯、预告与开播" => [
      {
        title: "Anime [Trailer] 2027",
        url: "https://example.com/news/1",
        source: "Crunchyroll News",
      },
    ],
  }
  rendered = AcgDailyBot.body(example, translations: { "Anime [Trailer] 2027" => "动画预告 2027" })
  if rendered["[动画预告 2027]"].nil? || rendered["原标题：Anime \\[Trailer\\] 2027"].nil?
    raise "Translation rendering failed"
  end
  if AcgDailyBot.body(example, translations: {})["翻译暂不可用，保留原文"].nil?
    raise "Translation fallback failed"
  end
  puts "ACG bot self-check passed"
elsif defined?(Rails) && !ARGV.delete("--load-only")
  File.open("/shared/state/acg-daily.lock", File::RDWR | File::CREAT, 0o600) do |lock|
    exit unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    AcgDailyBot.run(
      publish: ARGV.delete("--publish"),
      prepare_translations: ARGV.delete("--prepare-translations"),
    )
  end
end
