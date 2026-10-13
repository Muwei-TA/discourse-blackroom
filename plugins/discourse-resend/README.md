# Resend email delivery

This deployment plugin sends Discourse mail through `https://api.resend.com/emails` when `smtp_address` is `smtp.resend.com`. It uses `smtp_password` as the API key. Other SMTP providers keep their existing transport.

Install this directory in `plugins/discourse-resend`, persist it in the deployment configuration, and restart the application. Use a verified domain for `notification_email` and a domain-restricted sending key. Never commit the key.

The adapter preserves text and HTML bodies, recipients, attachments, and conversation headers. API failures raise errors so failed deliveries are not logged as sent. Repeated delivery of the same message uses the same idempotency key.

Run the focused check from the Discourse directory:

```sh
bundle exec ruby plugins/discourse-resend/test_delivery.rb
```

Verify the actual login-code and invitation flows, check `resend emails list` for delivery status, and confirm the messages in the recipient's mailbox, including spam. To restore SMTP delivery, remove the plugin and restart the application; restore the saved deployment configuration to return to the previous provider.
