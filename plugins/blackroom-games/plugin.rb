# frozen_string_literal: true

# name: blackroom-games
# about: Authorizes games against the member's current forum session.
# version: 0.2
# authors: BlackRoom

require_relative "lib/blackroom_games"

after_initialize do
  register_svg_icon "gamepad"

  add_to_serializer(:site, :blackroom_games) do
    BlackRoomGames.public_config.slice("category_id", "forum_origin")
  end

  add_to_serializer(:topic_view, :blackroom_game) do
    data = BlackRoomGames.public_config
    game = data["games"].find { |entry| entry["topic_id"] == object.topic.id }
    if game && object.topic.category_id == data["category_id"]
      game.merge("forum_origin" => data["forum_origin"])
    end
  end

  Rails.application.config.filter_parameters += %i[ticket grant browser_state]

  module ::BlackRoomGames
    class Engine < ::Rails::Engine
      engine_name "blackroom_games"
      isolate_namespace BlackRoomGames
    end

    class GamesController < ::ApplicationController
      prepend_view_path File.expand_path("app/views", __dir__)
      skip_before_action :check_xhr,
                         :redirect_to_login_if_required,
                         :block_if_requires_login,
                         only: %i[exchange verify profile entry open]
      skip_before_action :verify_authenticity_token, only: %i[exchange verify profile]
      before_action :ensure_logged_in, only: %i[catalog open entry]
      before_action :authenticate_gateway!, only: %i[exchange verify profile]

      def catalog
        BlackRoomGames.check_user!(current_user)
        render json: BlackRoomGames.public_config
      end

      def entry
        BlackRoomGames.check_user!(current_user)
        game = BlackRoomGames.game!(params.require(:game))
        room = params[:room]
        if room.present? && !room.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
          raise Discourse::InvalidParameters.new(:room)
        end
        target = "#{BlackRoomGames.config.fetch("forum_origin")}/t/topic/#{game.fetch("topic_id")}"
        target += "?room=#{room}" if room.present?
        redirect_to target, allow_other_host: true
      end

      def open
        unless request.headers["Origin"] == BlackRoomGames.config.fetch("forum_origin")
          raise Discourse::InvalidAccess
        end
        token = request.env[Auth::DefaultCurrentUserProvider::USER_TOKEN_KEY]
        if !token || token.user != current_user || current_user.is_impersonating
          raise Discourse::InvalidAccess
        end
        RateLimiter.new(current_user, "blackroom-games-launch", 10, 1.minute).performed!
        @game = BlackRoomGames.game!(params.require(:game))
        @room = params[:room].to_s
        if @room.present? && !@room.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
          raise Discourse::InvalidParameters.new(:room)
        end
        @state = SecureRandom.hex(32)
        @ticket = BlackRoomGames.launch(current_user, token, params.require(:game), @state)
        @nonce = SecureRandom.base64(24)
        response.headers[
          "Content-Security-Policy"
        ] = "default-src 'none'; script-src 'nonce-#{@nonce}'; style-src 'nonce-#{@nonce}'; form-action #{@game.fetch("origin")}; base-uri 'none'; frame-ancestors 'none'"
        response.headers["Referrer-Policy"] = "strict-origin"
        response.headers["Cache-Control"] = "no-store"
        render "black_room_games/games/open", layout: false
      end

      def exchange
        grant =
          BlackRoomGames.exchange(
            params.require(:ticket),
            params.require(:game),
            params.require(:browser_state),
          )
        response.headers["Cache-Control"] = "no-store"
        render json: { grant: grant }, status: :created
      end

      def verify
        BlackRoomGames.verify!(params.require(:grant), params.require(:game))
        response.headers["Cache-Control"] = "no-store"
        head :no_content
      end

      def profile
        response.headers["Cache-Control"] = "no-store"
        render json: BlackRoomGames.profile(params.require(:grant), params.require(:game))
      end

      private

      def authenticate_gateway!
        expected = BlackRoomGames.config.fetch("gateway_key")
        supplied = request.headers["X-Blackroom-Games-Key"].to_s
        if expected.bytesize < 32 ||
             !ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
          raise Discourse::InvalidAccess
        end
      end
    end
  end

  BlackRoomGames::Engine.routes.draw do
    get "/catalog" => "games#catalog"
    get "/entry/:game" => "games#entry"
    post "/open/:game" => "games#open"
    post "/exchange" => "games#exchange"
    post "/verify" => "games#verify"
    post "/profile" => "games#profile"
  end
  Discourse::Application.routes.append { mount ::BlackRoomGames::Engine, at: "/blackroom-games" }
end
