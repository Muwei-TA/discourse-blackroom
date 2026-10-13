# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "uri"

module BlackRoomGames
  def self.config
    data =
      JSON.parse(
        File.read(ENV.fetch("BLACKROOM_GAMES_CONFIG", "/shared/state/blackroom-games/forum.json")),
      )
    raise ArgumentError unless data.is_a?(Hash)
    data["forum_origin"] ||= (
      if ENV["BLACKROOM_GAMES_CONFIG"]
        Discourse.base_url
      else
        "https://discourse.muwei.xyz"
      end
    )
    raise ArgumentError unless valid_origin?(data["forum_origin"])
    unless data["gateway_key"].is_a?(String) && data["gateway_key"].bytesize >= 32
      raise ArgumentError
    end
    raise ArgumentError unless data["games"].is_a?(Array)
    if data["games"].any?
      raise ArgumentError unless data["category_id"].is_a?(Integer) && data["category_id"].positive?
    end
    data["games"].each do |game|
      unless game.is_a?(Hash) && game["id"].is_a?(String) &&
               game["id"].match?(/\A[a-z][a-z0-9-]*\z/)
        raise ArgumentError
      end
      unless valid_origin?(game["origin"]) && game["topic_id"].is_a?(Integer) &&
               game["topic_id"].positive?
        raise ArgumentError
      end
      raise ArgumentError unless %w[title description].all? { |field| game[field].is_a?(String) }
    end
    %w[id topic_id origin].each do |field|
      unless data["games"].map { |game| game[field] }.uniq.size == data["games"].size
        raise ArgumentError
      end
    end
    data
  rescue SystemCallError, JSON::ParserError, ArgumentError
    raise Discourse::InvalidAccess
  end

  def self.valid_origin?(value)
    return false unless value.is_a?(String)
    uri = URI.parse(value)
    scheme_allowed =
      uri.scheme == "https" ||
        (
          ENV["BLACKROOM_GAMES_CONFIG"] && uri.scheme == "http" &&
            uri.host.to_s.end_with?(".localhost")
        )
    scheme_allowed && uri.host && !uri.userinfo && !uri.query && !uri.fragment && uri.path.empty?
  rescue URI::InvalidURIError
    false
  end

  def self.public_config
    data = config
    {
      "category_id" => data["category_id"],
      "forum_origin" => data["forum_origin"],
      "games" =>
        data["games"].map { |game| game.slice("id", "title", "description", "origin", "topic_id") },
    }
  rescue Discourse::InvalidAccess
    { "category_id" => nil, "forum_origin" => "https://discourse.muwei.xyz", "games" => [] }
  end

  def self.game!(game)
    entry = config.fetch("games").find { |candidate| candidate["id"] == game }
    unless entry &&
             Topic.exists?(
               id: entry["topic_id"],
               category_id: config["category_id"],
               deleted_at: nil,
             )
      raise Discourse::InvalidAccess
    end
    entry
  end

  def self.check_user!(user)
    category = Category.find_by(id: config.fetch("category_id"))
    if !user || !user.active || user.suspended? || !user.approved? || !category ||
         !user.guardian.can_see_category?(category)
      raise Discourse::InvalidAccess
    end
  end

  def self.key(kind, value)
    raise Discourse::InvalidAccess if !value.is_a?(String) || !value.match?(/\A[0-9a-f]{64}\z/)
    "blackroom-games:#{kind}:#{Digest::SHA256.hexdigest(value)}"
  end

  def self.launch(user, token, game, browser_state)
    game!(game)
    key("state", browser_state)
    check_user!(user)
    raise Discourse::InvalidAccess if !UserAuthToken.unexpired.exists?(id: token.id)
    ticket = SecureRandom.hex(32)
    data = {
      "game" => game,
      "browser_state" => browser_state,
      "user_id" => user.id,
      "token_id" => token.id,
    }
    Discourse.redis.setex(key("ticket", ticket), 60, data.to_json)
    ticket
  end

  def self.exchange(ticket, game, browser_state)
    game!(game)
    raw = Discourse.redis.getdel(key("ticket", ticket))
    raise Discourse::InvalidAccess if !raw
    data = JSON.parse(raw)
    raise Discourse::InvalidAccess if data["game"] != game || data["browser_state"] != browser_state
    valid_session!(data)
    grant = SecureRandom.hex(32)
    Discourse.redis.setex(key("grant", grant), 8.hours.to_i, data.except("browser_state").to_json)
    grant
  end

  def self.verify!(grant, game)
    game!(game)
    raw = Discourse.redis.get(key("grant", grant))
    raise Discourse::InvalidAccess if !raw
    data = JSON.parse(raw)
    raise Discourse::InvalidAccess if data["game"] != game
    valid_session!(data)
  end

  def self.valid_session!(data)
    token = UserAuthToken.unexpired.find_by(id: data.fetch("token_id"))
    if !token || token.impersonated_user_id || token.user_id != data.fetch("user_id")
      raise Discourse::InvalidAccess
    end
    check_user!(token.user)
    token.user
  end

  def self.profile(grant, game)
    user = verify!(grant, game)
    { "username" => user.username }
  end
end
