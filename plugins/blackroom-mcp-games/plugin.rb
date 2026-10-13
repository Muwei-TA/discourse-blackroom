# frozen_string_literal: true

# name: blackroom-mcp-games
# about: Read the game catalog and prepare administrator registration proposals.
# version: 0.1
# authors: BlackRoom

after_initialize do
  require_relative "lib/games"

  register_mcp_tool(
    "discourse_list_games",
    title: "List games",
    description:
      "Lists games available to the authenticated member, with discussion and browser entry links. Does not issue launch tickets or report game health.",
    implementation: BlackroomMcpGames::ListGames,
    input_schema: {
      type: "object",
      properties: {
      },
      additionalProperties: false
    },
    output_schema:
      DiscourseMcp::OutputSchema.object(
        forum_origin: DiscourseMcp::OutputSchema::STRING,
        category_id: DiscourseMcp::OutputSchema::INTEGER,
        games: DiscourseMcp::OutputSchema::OBJECT_ARRAY
      ),
    required_scopes: [DiscourseMcp::Scopes::CONTENT_READ],
    annotations: DiscourseMcp::CorePrimitives::READ_ONLY,
    risk: :read
  )

  register_mcp_tool(
    "discourse_prepare_game_registration",
    title: "Prepare game registration",
    description:
      "Administrator-only dry run: validates a new game and returns a registration proposal and deployment checklist. Does not fetch addresses, save configuration, create topics, deploy containers, or open public access. A missing topic_id requires a new staff-managed discussion topic before deployment.",
    implementation: BlackroomMcpGames::PrepareRegistration,
    input_schema: {
      type: "object",
      properties: {
        id: {
          type: "string",
          pattern: "^[a-z][a-z0-9-]*$",
          maxLength: 80
        },
        title: {
          type: "string",
          minLength: 1,
          maxLength: 200
        },
        description: {
          type: "string",
          maxLength: 2000
        },
        origin: {
          type: "string",
          maxLength: 500
        },
        upstream: {
          type: "string",
          maxLength: 500
        },
        websocket_paths: {
          type: "array",
          maxItems: 20,
          items: {
            type: "object",
            properties: {
              path: {
                type: "string",
                maxLength: 200
              },
              match: {
                type: "string",
                enum: %w[exact prefix]
              }
            },
            required: %w[path match],
            additionalProperties: false
          }
        },
        topic_id: {
          type: "integer",
          minimum: 1
        }
      },
      required: %w[id title description origin upstream websocket_paths],
      additionalProperties: false
    },
    output_schema:
      DiscourseMcp::OutputSchema.object(
        status: DiscourseMcp::OutputSchema::STRING,
        applied: DiscourseMcp::OutputSchema::BOOLEAN,
        category_id: DiscourseMcp::OutputSchema::INTEGER,
        manifest_entry: DiscourseMcp::OutputSchema::OBJECT,
        forum_entry: DiscourseMcp::OutputSchema::OBJECT,
        checklist: DiscourseMcp::OutputSchema::STRING_ARRAY
      ),
    required_scopes: [DiscourseMcp::Scopes::SITE_SETTINGS_READ],
    annotations: DiscourseMcp::CorePrimitives::READ_ONLY,
    risk: :read
  )
end
