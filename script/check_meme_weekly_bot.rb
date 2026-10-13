# frozen_string_literal: true

require "tmpdir"
require_relative "meme_weekly_bot"

Dir.mktmpdir do |root|
  items = 12.times.map do |index|
    File.write(File.join(root, "#{index}.png"), "fixture #{index}")
    { "author" => "作者 #{index}", "source_url" => "https://example.com/#{index}", "file" => "#{index}.png", "reviewed" => true, "reason" => "比例反差", "rights_basis" => "测试样本" }
  end
  manifest = { "date" => "2026-10-09", "items" => items }
  issue = MemeWeeklyBot.validate(manifest, root: root)
  raise "Valid issue rejected" unless issue[:hashes].size == 12
  reject = lambda do |candidate, seen = []|
    begin
      MemeWeeklyBot.validate(candidate, root: root, seen: seen)
    rescue StandardError
      next
    end
    raise "Invalid issue accepted"
  end
  reject.call(manifest.merge("date" => "2026-10-08"))
  raise "Explicit test issue rejected" unless MemeWeeklyBot.validate(manifest.merge("date" => "2026-10-08"), root: root, test: true)[:date] == Date.new(2026, 10, 8)
  raise "Short test issue rejected" unless MemeWeeklyBot.validate(manifest.merge("date" => "2026-10-08", "items" => items.first(4)), root: root, test: true)[:items].size == 4
  reject.call(manifest.merge("items" => items.first(11)))
  reject.call(manifest.merge("items" => items + items))
  reject.call(manifest.merge("items" => items.map { |item| item.merge("reviewed" => false) }))
  reject.call(manifest.merge("items" => items.map { |item| item.merge("source_url" => "http://example.com") }))
  reject.call(manifest.merge("items" => items.map { |item| item.merge("author" => "") }))
  reject.call(manifest.merge("items" => items.map { |item| item.merge("license" => "CC BY 2.0", "license_url" => "https://evil.example/license") }))
  licensed = items.map { |item| item.merge("license" => "CC BY 2.0", "license_url" => "https://creativecommons.org/licenses/by/2.0/") }
  raise "Licensed issue rejected" unless MemeWeeklyBot.validate(manifest.merge("items" => licensed), root: root)[:items].size == 12
  reject.call(manifest.merge("items" => items.map { |item| item.merge("file" => "../missing.png") }))
  reject.call(manifest.merge("items" => [items.first] * 12))
  reject.call(manifest, [issue[:hashes].first])
  reject.call(manifest, [items.first.fetch("source_url")])
end
puts "Meme weekly validation self-check passed"
