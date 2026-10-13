# frozen_string_literal: true

require "tmpdir"
require_relative "../lib/blackroom_games"

module Discourse
  class InvalidAccess < StandardError
  end

  def self.base_url
    "http://forum.games.localhost:18190"
  end
end

assert = ->(value) { raise "assertion failed" unless value }

previous = ENV["BLACKROOM_GAMES_CONFIG"]
begin
  Dir.mktmpdir do |dir|
    path = File.join(dir, "forum.json")
    ENV["BLACKROOM_GAMES_CONFIG"] = path
    valid = {
      "forum_origin" => "https://discourse.muwei.xyz",
      "category_id" => 5,
      "gateway_key" => "x" * 64,
      "games" => [
        {
          "id" => "bonk",
          "topic_id" => 7,
          "title" => "Bonk",
          "description" => "Play",
          "origin" => "https://bonk.muwei.xyz",
          "upstream" => "private",
        },
      ],
    }
    File.write(path, valid.to_json)
    assert.call(BlackRoomGames.config["category_id"] == 5)
    assert.call(!BlackRoomGames.public_config.to_json.include?("gateway_key"))
    assert.call(!BlackRoomGames.public_config.to_json.include?("private"))
    assert.call(BlackRoomGames.valid_origin?("http://forum.games.localhost:18190"))
    [
      "http://example.com",
      "https://user:secret@example.com",
      "https://example.com/path",
      "https://example.com?key=x",
      "https://example.com#fragment",
      nil,
    ].each { |origin| assert.call(!BlackRoomGames.valid_origin?(origin)) }
    [
      "{",
      "null",
      "[]",
      valid.merge("gateway_key" => "short").to_json,
      valid.merge("games" => [nil]).to_json,
      valid.merge("games" => valid["games"] * 2).to_json,
      valid.merge("category_id" => "5").to_json,
    ].each do |raw|
      File.write(path, raw)
      assert.call(BlackRoomGames.public_config["games"].empty?)
      begin
        BlackRoomGames.config
        raise "bad config accepted"
      rescue Discourse::InvalidAccess
        nil
      end
    end
    File.write(path, valid.merge("games" => [], "category_id" => nil).to_json)
    assert.call(BlackRoomGames.config["games"].empty?)
    File.delete(path)
    assert.call(BlackRoomGames.public_config["games"].empty?)
  end
ensure
  ENV["BLACKROOM_GAMES_CONFIG"] = previous
end
puts "config validation and failure isolation passed"
