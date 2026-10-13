# frozen_string_literal: true

# name: blackroom-mcp-images
# about: Return images from visible posts through MCP
# version: 0.1
# authors: Muwei

after_initialize do
  require_relative "lib/read_post_image"

  register_mcp_tool(
    "discourse_read_post_image",
    title: "Read post image",
    description:
      "Returns one uploaded image from a visible post as MCP image content. image_index is 1-based, ordered by upload ID; defaults to 1. The result includes an image inventory for subsequent calls. External hotlinks are excluded.",
    implementation: BlackroomMcpImages::ReadPostImage,
    input_schema: {
      type: "object",
      properties: {
        post_id: {
          type: "integer",
          minimum: 1
        },
        image_index: {
          type: "integer",
          minimum: 1,
          default: 1
        }
      },
      required: %w[post_id],
      additionalProperties: false
    },
    output_schema: BlackroomMcpImages::ReadPostImage::OUTPUT_SCHEMA,
    required_scopes: [DiscourseMcp::Scopes::CONTENT_READ],
    annotations: DiscourseMcp::CorePrimitives::READ_ONLY,
    risk: :read
  )
end
