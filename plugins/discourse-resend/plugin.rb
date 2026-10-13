# frozen_string_literal: true

# name: discourse-resend
# about: Deliver transactional email through the Resend API
# version: 0.1
# authors: Muwei

require_relative "lib/resend_delivery"

after_initialize do
  if GlobalSetting.smtp_address == "smtp.resend.com"
    ActionMailer::Base.add_delivery_method(
      :resend,
      DiscourseResend::Delivery,
      api_key: GlobalSetting.smtp_password,
    )
    ActionMailer::Base.delivery_method = :resend
  end
end
