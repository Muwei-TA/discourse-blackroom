# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"

module DiscourseResend
  class Delivery
    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      raise ArgumentError, "Missing email delivery API key" if settings[:api_key].to_s.empty?

      payload = { from: mail[:from].decoded, to: mail.to, subject: mail.subject }
      %i[cc bcc reply_to].each do |field|
        payload[field] = mail.public_send(field) if mail.public_send(field)&.any?
      end
      if mail.multipart?
        payload[:html] = mail.html_part.body.decoded if mail.html_part
        payload[:text] = mail.text_part.body.decoded if mail.text_part
      else
        payload[mail.mime_type == "text/html" ? :html : :text] = mail.body.decoded
      end
      payload[:attachments] = mail.attachments.map do |attachment|
        item = { filename: attachment.filename, content: Base64.strict_encode64(attachment.decoded) }
        item[:content_type] = attachment.mime_type
        item[:content_id] = attachment.cid if attachment.inline?
        item
      end
      payload[:headers] = mail.header.fields.each_with_object({}) do |field, headers|
        if field.name.match?(/\A(X-|Message-ID\z|In-Reply-To\z|References\z|Auto-Submitted\z)/i)
          headers[field.name] = field.decoded
        end
      end

      uri = URI("https://api.resend.com/emails")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{settings[:api_key]}"
      request["Content-Type"] = "application/json"
      request["Idempotency-Key"] = Digest::SHA256.hexdigest(mail.message_id || mail.encoded)
      request.body = JSON.generate(payload)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise IOError, "Email delivery API returned HTTP #{response.code}"
      end
      result = JSON.parse(response.body)
      raise IOError, "Email delivery API returned no message ID" if result["id"].to_s.empty?
      result
    end
  end
end
