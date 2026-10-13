# frozen_string_literal: true

require "base64"

module BlackroomMcpImages
  class ReadPostImage
    MIME_TYPES = {
      "png" => "image/png",
      "jpg" => "image/jpeg",
      "jpeg" => "image/jpeg",
      "gif" => "image/gif",
      "webp" => "image/webp"
    }.freeze
    OUTPUT_SCHEMA =
      DiscourseMcp::OutputSchema.object(
        post_id: DiscourseMcp::OutputSchema::INTEGER,
        image_index: DiscourseMcp::OutputSchema::INTEGER,
        images: DiscourseMcp::OutputSchema::OBJECT_ARRAY,
        resized: DiscourseMcp::OutputSchema::BOOLEAN
      )

    def self.call(arguments:, request_context:)
      post =
        DiscourseMcp::ToolHelpers.visible_post!(
          arguments.fetch("post_id"),
          request_context
        )
      images =
        post
          .uploads
          .where(extension: MIME_TYPES.keys)
          .order(:id)
          .select do |upload|
            request_context.guardian.can_see_upload?(upload) &&
              (
                !upload.access_control_post&.topic&.private_message? ||
                  request_context.has_scopes?(
                    [DiscourseMcp::Scopes::PRIVATE_MESSAGES_READ]
                  )
              )
          end
      index = arguments.fetch("image_index", 1)
      upload = index.positive? ? images[index - 1] : nil
      if upload.nil?
        raise DiscourseMcp::ToolError, "No readable image at this image_index"
      end

      maximum_size = ((SiteSetting.mcp_max_response_bytes - 16_384) * 3) / 4
      image = upload
      if upload.filesize > maximum_size
        image =
          upload
            .optimized_images
            .where("filesize <= ?", maximum_size)
            .order(width: :desc)
            .first
      end
      # shortcut: oversized images need an existing thumbnail; add on-demand resizing if required.
      if image.nil?
        raise DiscourseMcp::ToolError, "Image exceeds the MCP response limit"
      end

      mime_type = MIME_TYPES[image.extension]
      if mime_type.nil?
        raise DiscourseMcp::ToolError, "Unsupported image format"
      end

      path =
        if Discourse.store.external?
          Discourse.store.download(image, max_file_size_kb: maximum_size)
        else
          Discourse.store.path_for(image)
        end
      raise DiscourseMcp::ToolError, "Image file is unavailable" if path.blank?

      data = File.binread(path, maximum_size + 1)
      raise DiscourseMcp::ToolError, "Image file is unavailable" if data.empty?
      if data.bytesize > maximum_size
        raise DiscourseMcp::ToolError, "Image exceeds the MCP response limit"
      end

      result =
        DiscourseMcp::ToolHelpers.text_and_structured(
          post_id: post.id,
          image_index: index,
          images:
            images.each_with_index.map do |item, position|
              {
                image_index: position + 1,
                upload_id: item.id,
                filename: item.original_filename,
                width: item.width,
                height: item.height
              }
            end,
          resized: image != upload
        )
      result[:content] << {
        type: "image",
        data: Base64.strict_encode64(data),
        mimeType: mime_type
      }
      result
    rescue Errno::ENOENT, Errno::EACCES
      raise DiscourseMcp::ToolError, "Image file is unavailable"
    end
  end
end
