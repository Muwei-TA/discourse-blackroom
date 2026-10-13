# frozen_string_literal: true

require "mail"
require_relative "lib/resend_delivery"

mail = Mail.new do
  from "BlackRoom <noreply@example.com>"
  to "member@example.com"
  subject "Delivery check"
  message_id "delivery-check@example.com"
  text_part { body "Plain content" }
  html_part { content_type "text/html; charset=UTF-8"; body "<p>HTML content</p>" }
end
mail.bcc = ["hidden@example.com"]
mail.reply_to = ["reply@example.com"]
mail["X-Discourse-Test"] = "check"
mail.attachments["check.txt"] = "Attachment content"

requests = []
response = Net::HTTPOK.new("1.1", "200", "OK")
response.instance_variable_set(:@read, true)
response.body = '{"id":"delivery-check"}'
http = Object.new
http.define_singleton_method(:request) { |request| requests << request; response }
Net::HTTP.define_singleton_method(:start) { |*args, **options, &block| block.call(http) }

delivery = DiscourseResend::Delivery.new(api_key: "test-only")
2.times { raise "Missing response ID" unless delivery.deliver!(mail)["id"] == "delivery-check" }
payload = JSON.parse(requests.first.body)
raise "Missing bodies" unless payload.values_at("text", "html") == ["Plain content", "<p>HTML content</p>"]
raise "Missing recipients" unless payload["to"] == ["member@example.com"] && payload["bcc"] == ["hidden@example.com"]
raise "Missing attachment" unless Base64.decode64(payload["attachments"].first["content"]) == "Attachment content"
raise "Missing header" unless payload["headers"]["X-Discourse-Test"] == "check"
raise "Unstable deduplication" unless requests.map { |request| request["Idempotency-Key"] }.uniq.size == 1

response = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests")
begin
  delivery.deliver!(mail)
  raise "Failed delivery accepted"
rescue IOError
end
puts "Email delivery checks passed"
