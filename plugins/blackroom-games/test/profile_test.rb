# frozen_string_literal: true

require_relative "../lib/blackroom_games"

module Discourse
  class InvalidAccess < StandardError
  end

  def self.redis
    @redis ||= Object.new.tap { |store| def store.get(key) = @records.fetch(key, nil) }
  end
end

module UserAuthToken
  class << self
    attr_accessor :tokens
    def unexpired = self
    def find_by(id:) = tokens[id]
  end
end

module BlackRoomGames
  def self.game!(game)
    raise Discourse::InvalidAccess if game != "bonk" && game != "skribbl"
  end

  def self.check_user!(user)
    raise Discourse::InvalidAccess unless user.allowed
  end
end

user = Struct.new(:username, :allowed).new("站点玩家", true)
token = Struct.new(:user_id, :impersonated_user_id, :user).new(7, nil, user)
UserAuthToken.tokens = { 12 => token }
grant = "a" * 64
record = { "game" => "bonk", "user_id" => 7, "token_id" => 12 }
Discourse.redis.instance_variable_set(
  :@records,
  BlackRoomGames.key("grant", grant) => record.to_json,
)
assert = ->(value) { raise "assertion failed" unless value }
assert.call(BlackRoomGames.profile(grant, "bonk") == { "username" => "站点玩家" })
user.username = "新的用户名"
assert.call(BlackRoomGames.profile(grant, "bonk") == { "username" => "新的用户名" })
reject =
  lambda do |&action|
    action.call
    raise "invalid authorization accepted"
  rescue Discourse::InvalidAccess
    nil
  end
reject.call { BlackRoomGames.profile("invalid", "bonk") }
reject.call { BlackRoomGames.profile("b" * 64, "bonk") }
reject.call { BlackRoomGames.profile(grant, "skribbl") }
reject.call { BlackRoomGames.profile(grant, "unknown") }
user.allowed = false
reject.call { BlackRoomGames.profile(grant, "bonk") }
user.allowed = true
token.impersonated_user_id = 3
reject.call { BlackRoomGames.profile(grant, "bonk") }
token.impersonated_user_id = nil
token.user_id = 8
reject.call { BlackRoomGames.profile(grant, "bonk") }
UserAuthToken.tokens = {}
reject.call { BlackRoomGames.profile(grant, "bonk") }
puts "current username, rename, revoked and mismatched session profile checks passed"
