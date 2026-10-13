# frozen_string_literal: true

require "uri"

module BlackroomMcpGames
  def self.config!(context)
    unless defined?(BlackRoomGames)
      raise DiscourseMcp::ToolError, "The games platform is unavailable"
    end
    BlackRoomGames.check_user!(context.user)
    BlackRoomGames.config
  end

  class ListGames
    def self.call(arguments:, request_context:)
      config = BlackroomMcpGames.config!(request_context)
      games =
        config
          .fetch("games")
          .filter_map do |game|
            topic =
              Topic.find_by(
                id: game.fetch("topic_id"),
                category_id: config.fetch("category_id"),
                deleted_at: nil
              )
            next unless topic && request_context.guardian.can_see_topic?(topic)

            game.slice(
              "id",
              "title",
              "description",
              "origin",
              "topic_id"
            ).merge(
              "discussion_url" =>
                "#{config.fetch("forum_origin")}/t/topic/#{topic.id}",
              "entry_url" =>
                "#{config.fetch("forum_origin")}/blackroom-games/entry/#{game.fetch("id")}",
              "requires_browser_login" => true
            )
          end
      DiscourseMcp::ToolHelpers.text_and_structured(
        forum_origin: config.fetch("forum_origin"),
        category_id: config.fetch("category_id"),
        games: games
      )
    end
  end

  class PrepareRegistration
    def self.call(arguments:, request_context:)
      request_context.guardian.ensure_is_admin!
      config = BlackroomMcpGames.config!(request_context)
      id = arguments.fetch("id")
      if !id.match?(/\A[a-z][a-z0-9-]*\z/) ||
           %w[constructor prototype].include?(id)
        raise DiscourseMcp::ToolError, "Invalid game ID"
      end
      if arguments.fetch("title").strip.empty?
        raise DiscourseMcp::ToolError, "A game title is required"
      end
      origin = arguments.fetch("origin")
      validate_origin!(origin, %w[https])
      validate_origin!(arguments.fetch("upstream"), %w[http https])
      if origin == config.fetch("forum_origin") ||
           config
             .fetch("games")
             .any? { |game| game["id"] == id || game["origin"] == origin }
        raise DiscourseMcp::ToolError,
              "Game ID or public origin is already registered"
      end
      arguments
        .fetch("websocket_paths")
        .each do |rule|
          path = rule.fetch("path")
          unless path.match?(%r{\A/[A-Za-z0-9_./-]*\z}) &&
                   !path.start_with?("//", "/_blackroom") &&
                   (path.split("/") & %w[. ..]).empty? &&
                   %w[exact prefix].include?(rule.fetch("match"))
            raise DiscourseMcp::ToolError, "Invalid WebSocket rule"
          end
        end
      topic_id = arguments["topic_id"]
      if topic_id
        topic =
          Topic.find_by(
            id: topic_id,
            category_id: config.fetch("category_id"),
            deleted_at: nil
          )
        unless topic && request_context.guardian.can_see_topic?(topic) &&
                 config
                   .fetch("games")
                   .none? { |game| game["topic_id"] == topic_id }
          raise DiscourseMcp::ToolError,
                "Topic must be an unregistered, visible game-category topic"
        end
      end
      DiscourseMcp::ToolHelpers.text_and_structured(
        status: "prepared",
        applied: false,
        category_id: config.fetch("category_id"),
        manifest_entry:
          arguments.slice(
            "id",
            "title",
            "description",
            "origin",
            "upstream",
            "websocket_paths"
          ),
        forum_entry:
          arguments.slice("id", "title", "description", "origin").merge(
            "topic_id" => topic_id
          ),
        checklist: [
          "Confirm the game build, resource paths, Host/Origin support and invitation room parameter.",
          "Create or verify the staff-managed discussion topic in the game category; record its real topic_id.",
          "Back up the current NAS manifest and private configuration; append the proposal without replacing existing games.",
          "Generate private forum/gateway files with the existing renderConfigs/prepareRelease tools; never include service keys in MCP output.",
          "Obtain specific authorization before deploying the game, its isolated backend/gateway and public domain route.",
          "Check anonymous denial, member launch, invitations, real gameplay and logout/suspension revocation before opening the catalog entry.",
          "The catalog renders new entries automatically; add the new cover to the theme separately."
        ]
      )
    end

    def self.validate_origin!(value, schemes)
      uri = URI.parse(value)
      valid =
        schemes.include?(uri.scheme) && uri.host && !uri.userinfo &&
          !uri.query && !uri.fragment && uri.path.empty? &&
          uri.host == uri.host.downcase && uri.port&.between?(1, 65_535) &&
          value ==
            "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? "" : ":#{uri.port}"}"
      unless valid
        raise DiscourseMcp::ToolError,
              "Use a canonical origin without credentials, path, query or fragment"
      end
    rescue URI::InvalidURIError
      raise DiscourseMcp::ToolError, "Invalid origin"
    end
  end
end
