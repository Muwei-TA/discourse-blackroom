# frozen_string_literal: true

# Run with Rails runner; all database fixtures and MCP audit rows are rolled back.
require "ostruct"

module BlackroomMcpImagesCheck
  module_function

  loader = Object.new
  def loader.after_initialize(&block)
    instance_eval(&block)
  end

  def loader.register_mcp_tool(identifier, **attributes)
    DiscourseMcp.registry.register_tool(
      identifier,
      provider: "blackroom-mcp-images",
      **attributes
    )
  end
  unless DiscourseMcp.registry.find(:tool, "discourse_read_post_image")
    loader.instance_eval(
      File.read(File.join(__dir__, "plugin.rb")),
      File.join(__dir__, "plugin.rb")
    )
  end

  def image_check!(condition, description)
    raise "Failed: #{description}" unless condition
  end

  def image_probe(
    user,
    post_id,
    index: 1,
    scopes: [DiscourseMcp::Scopes::CONTENT_READ]
  )
    token = OpenStruct.new(user_id: user.id, scopes:)
    context = DiscourseMcp::RequestContext.new(token)
    request =
      ActionDispatch::Request.new(
        Rack::MockRequest.env_for("#{Discourse.base_url}/mcp")
      )
    request.headers[
      "MCP-Protocol-Version"
    ] = DiscourseMcp::LEGACY_PROTOCOL_VERSION
    DiscourseMcp::Server.new(request:, request_context: context).call(
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => {
        "name" => "discourse_read_post_image",
        "arguments" => {
          "post_id" => post_id,
          "image_index" => index
        }
      }
    )
  end

  checks = []
  fixture_ids = []
  ActiveRecord::Base.transaction do
    policy =
      McpPrimitive.find_or_initialize_by(
        kind: "tool",
        identifier: "discourse_read_post_image"
      )
    policy.update!(enabled: true, emergency_blocked: false)
    upload =
      Upload
        .where(secure: false, extension: %w[png jpg jpeg gif webp])
        .detect do |item|
          path = Discourse.store.path_for(item)
          item.access_control_post_id.nil? && path && File.file?(path) &&
            File.size(path) < 1.megabyte
        end
    raise "A local non-secure image is needed for this check" unless upload

    groups =
      Group.where(name: %w[blackbox_animation blacklight_lit]).order(:id).to_a
    image_check!(groups.length == 2, "two club groups exist")
    users =
      3.times.map do |position|
        username = "mcp_image_probe_#{SecureRandom.hex(5)}"
        id =
          User
            .insert_all!(
              [
                {
                  username:,
                  username_lower: username,
                  active: true,
                  approved: true,
                  admin: false,
                  moderator: false,
                  trust_level: 1
                }
              ],
              returning: %w[id]
            )
            .rows
            .first
            .first
        fixture_ids << id
        if position < 2
          GroupUser.insert_all!(
            [{ group_id: groups[position].id, user_id: id, owner: false }]
          )
        end
        User.find(id)
      end
    category = Category.find_by!(name: groups.first.full_name)
    topic_id =
      Topic
        .insert_all!(
          [
            {
              title: "MCP image rollback probe",
              category_id: category.id,
              user_id: users.first.id,
              last_post_user_id: users.first.id,
              bumped_at: Time.zone.now,
              archetype: "regular",
              visible: true,
              posts_count: 1,
              highest_post_number: 1
            }
          ],
          returning: %w[id]
        )
        .rows
        .first
        .first
    post_id =
      Post
        .insert_all!(
          [
            {
              topic_id:,
              user_id: users.first.id,
              post_number: 1,
              last_version_at: Time.zone.now,
              raw: "image probe",
              cooked: "<p>image probe</p>",
              post_type: Post.types[:regular]
            }
          ],
          returning: %w[id]
        )
        .rows
        .first
        .first
    UploadReference.insert_all!(
      [{ upload_id: upload.id, target_type: "Post", target_id: post_id }]
    )

    member = image_probe(users.first, post_id)
    image_check!(
      member.http_status == 200 && !member.body.dig(:result, :isError),
      "member read"
    )
    image =
      member.body.dig(:result, :content).find { |item| item[:type] == "image" }
    expected = File.binread(Discourse.store.path_for(upload))
    image_check!(
      image && Base64.strict_decode64(image[:data]) == expected,
      "exact image bytes"
    )
    image_check!(
      image[:mimeType] ==
        BlackroomMcpImages::ReadPostImage::MIME_TYPES[upload.extension],
      "MIME type"
    )
    checks << "member image bytes and MIME"
    users
      .drop(1)
      .each do |user|
        denied = image_probe(user, post_id)
        image_check!(denied.body.dig(:result, :isError), "private post denied")
        image_check!(
          denied
            .body
            .dig(:result, :content)
            .none? { |item| item[:type] == "image" },
          "no image leak"
        )
      end
    checks << "other club and nonmember denied"
    admin = User.find(1)
    image_check!(
      !image_probe(admin, post_id).body.dig(:result, :isError),
      "administrator read"
    )
    checks << "administrator read"
    image_check!(
      image_probe(admin, post_id, scopes: []).http_status == 403,
      "scope denied"
    )
    image_check!(
      image_probe(admin, post_id, index: 0).body[:error].present?,
      "invalid index"
    )
    image_check!(
      image_probe(admin, post_id, index: 2).body.dig(:result, :isError),
      "missing image"
    )
    checks << "scope and index validation"

    missing_id =
      Upload
        .insert_all!(
          [
            {
              user_id: admin.id,
              sha1: SecureRandom.hex(20),
              extension: "png",
              filesize: 10,
              original_filename: "missing.png",
              url: "/uploads/mcp-image-probe-missing.png"
            }
          ],
          returning: %w[id]
        )
        .rows
        .first
        .first
    UploadReference.insert_all!(
      [{ upload_id: missing_id, target_type: "Post", target_id: post_id }]
    )
    missing = image_probe(admin, post_id, index: 2)
    image_check!(missing.body.dig(:result, :isError), "missing file error")
    image_check!(
      member.body.dig(:result, :structuredContent, :images).length == 1,
      "image inventory"
    )
    checks << "missing file and inventory"

    Upload.where(id: missing_id).update_all(url: upload.url)
    second = image_probe(admin, post_id, index: 2)
    image_check!(!second.body.dig(:result, :isError), "second image selection")
    image_check!(
      second.body.dig(:result, :structuredContent, :images).length == 2,
      "two-image inventory"
    )
    checks << "multiple image selection"

    Upload.where(id: missing_id).update_all(
      filesize: SiteSetting.mcp_max_response_bytes
    )
    oversized = image_probe(admin, post_id, index: 2)
    image_check!(oversized.body.dig(:result, :isError), "oversized file error")
    checks << "oversized image refused"

    OptimizedImage.insert_all!(
      [
        {
          upload_id: missing_id,
          sha1: SecureRandom.hex(20),
          extension: upload.extension,
          url: upload.url,
          width: upload.width,
          height: upload.height,
          filesize: expected.bytesize
        }
      ]
    )
    thumbnail = image_probe(admin, post_id, index: 2)
    image_check!(
      !thumbnail.body.dig(:result, :isError) &&
        thumbnail.body.dig(:result, :structuredContent, :resized),
      "existing thumbnail fallback"
    )
    checks << "existing thumbnail fallback"

    Topic.where(id: topic_id).update_all(
      archetype: "private_message",
      category_id: nil
    )
    image_check!(
      image_probe(admin, post_id).http_status == 403,
      "private message scope denied"
    )
    with_pm =
      image_probe(
        admin,
        post_id,
        scopes: [
          DiscourseMcp::Scopes::CONTENT_READ,
          DiscourseMcp::Scopes::PRIVATE_MESSAGES_READ
        ]
      )
    image_check!(
      !with_pm.body.dig(:result, :isError),
      "private message with scope"
    )
    checks << "private message scope enforced"
    raise ActiveRecord::Rollback
  end
  image_check!(User.where(id: fixture_ids).none?, "fixtures rolled back")
  puts JSON.generate(
         checks:,
         temporary_data_rolled_back: true,
         live_web_workers_changed: false
       )
end
