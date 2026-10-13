# frozen_string_literal: true

require "ostruct"

loader = Object.new
def loader.after_initialize(&block)
  instance_eval(&block)
end

def loader.register_mcp_tool(identifier, **attributes)
  DiscourseMcp.registry.register_tool(
    identifier,
    provider: "blackroom-mcp-games",
    **attributes
  )
end
loader.instance_eval(
  File.read(File.join(__dir__, "plugin.rb")),
  File.join(__dir__, "plugin.rb")
)

module BlackroomMcpGamesCheck
  module_function

  def probe(user, scopes, name, arguments = {})
    context =
      DiscourseMcp::RequestContext.new(
        OpenStruct.new(user_id: user.id, scopes: scopes)
      )
    request =
      ActionDispatch::Request.new(
        Rack::MockRequest.env_for("#{Discourse.base_url}/mcp")
      )
    request.headers[
      "MCP-Protocol-Version"
    ] = DiscourseMcp::LEGACY_PROTOCOL_VERSION
    DiscourseMcp::Server.new(request: request, request_context: context).call(
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => {
        "name" => name,
        "arguments" => arguments
      }
    )
  end
end

checks = []
assert = ->(value, label) do
  raise "Failed: #{label}" unless value
  checks << label
end
success = ->(response) do
  response.body[:result] && !response.body[:result][:isError]
end
ActiveRecord::Base.transaction do
  %w[discourse_list_games discourse_prepare_game_registration].each do |name|
    McpPrimitive.find_or_initialize_by(kind: "tool", identifier: name).update!(
      enabled: true,
      emergency_blocked: false
    )
  end
  admin = User.where(admin: true, active: true).where("id > 0").first!
  member =
    User
      .where(admin: false, moderator: false, active: true, approved: true)
      .where("id > 0")
      .detect do |user|
        !user.suspended? &&
          user.guardian.can_see_category?(
            Category.find(BlackRoomGames.config.fetch("category_id"))
          )
      end
  raise "A non-admin game member is required" unless member
  read = [DiscourseMcp::Scopes::CONTENT_READ]
  manage = [DiscourseMcp::Scopes::SITE_SETTINGS_READ]
  list = BlackroomMcpGamesCheck.probe(member, read, "discourse_list_games")
  assert.call(success.call(list), "member catalog through native MCP")
  data =
    JSON.parse(
      JSON.generate(list.body.fetch(:result).fetch(:structuredContent))
    )
  assert.call(
    data.fetch("games").length == BlackRoomGames.config.fetch("games").length,
    "registered games listed"
  )
  assert.call(
    !JSON.generate(data).match?(/gateway_key|upstream|ticket|grant/),
    "catalog contains no infrastructure credentials"
  )
  assert.call(
    !success.call(
      BlackroomMcpGamesCheck.probe(member, [], "discourse_list_games")
    ),
    "catalog scope enforced"
  )
  candidate = {
    "id" => "mcp-probe",
    "title" => "接入检查",
    "description" => "仅验证，不登记",
    "origin" => "https://mcp-probe.example.com",
    "upstream" => "http://probe-game:3000",
    "websocket_paths" => [{ "path" => "/socket.io/", "match" => "prefix" }]
  }
  before =
    File.binread(
      ENV.fetch(
        "BLACKROOM_GAMES_CONFIG",
        "/shared/state/blackroom-games/forum.json"
      )
    )
  response =
    BlackroomMcpGamesCheck.probe(
      admin,
      manage,
      "discourse_prepare_game_registration",
      candidate
    )
  assert.call(
    success.call(response),
    "administrator prepares registration through native MCP"
  )
  result =
    JSON.parse(
      JSON.generate(response.body.fetch(:result).fetch(:structuredContent))
    )
  assert.call(
    result["status"] == "prepared" && result["applied"] == false &&
      result["forum_entry"]["topic_id"].nil?,
    "proposal states unapplied and missing topic"
  )
  assert.call(
    File.binread(
      ENV.fetch(
        "BLACKROOM_GAMES_CONFIG",
        "/shared/state/blackroom-games/forum.json"
      )
    ) == before,
    "dry run leaves configuration unchanged"
  )
  assert.call(
    !success.call(
      BlackroomMcpGamesCheck.probe(
        member,
        manage,
        "discourse_prepare_game_registration",
        candidate
      )
    ),
    "non-admin rejected even with scope"
  )
  assert.call(
    !success.call(
      BlackroomMcpGamesCheck.probe(
        admin,
        read,
        "discourse_prepare_game_registration",
        candidate
      )
    ),
    "management scope enforced"
  )
  invalid = [
    { "id" => BlackRoomGames.config.fetch("games").first.fetch("id") },
    { "origin" => BlackRoomGames.config.fetch("games").first.fetch("origin") },
    { "origin" => "https://user:password@example.com" },
    { "origin" => "https://example.com/path" },
    { "origin" => "https://example.com:443" },
    { "upstream" => "file:///etc/passwd" },
    { "title" => "   " },
    { "websocket_paths" => [{ "path" => "/../ws", "match" => "exact" }] },
    {
      "websocket_paths" => [
        { "path" => "/_blackroom/open", "match" => "prefix" }
      ]
    },
    {
      "topic_id" => BlackRoomGames.config.fetch("games").first.fetch("topic_id")
    },
    { "topic_id" => 2_147_483_647 },
    { "extra" => "unrequested field" },
    { "title" => "x" * 201 }
  ]
  invalid.each_with_index do |change, index|
    assert.call(
      !success.call(
        BlackroomMcpGamesCheck.probe(
          admin,
          manage,
          "discourse_prepare_game_registration",
          candidate.merge(change)
        )
      ),
      "invalid candidate #{index + 1} rejected"
    )
  end
  assert.call(
    success.call(
      BlackroomMcpGamesCheck.probe(
        admin,
        manage,
        "discourse_prepare_game_registration",
        candidate.merge("websocket_paths" => [])
      )
    ),
    "static game without WebSocket accepted"
  )
  McpPrimitive.find_by!(
    kind: "tool",
    identifier: "discourse_prepare_game_registration"
  ).update!(enabled: false)
  assert.call(
    !success.call(
      BlackroomMcpGamesCheck.probe(
        admin,
        manage,
        "discourse_prepare_game_registration",
        candidate
      )
    ),
    "disabled tool rejected"
  )
  raise ActiveRecord::Rollback
end
puts JSON.generate(ok: true, checks: checks)
