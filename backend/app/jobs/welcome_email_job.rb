# frozen_string_literal: true

class WelcomeEmailJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(user_id, send_on_verify: false)
    user = User.find_by(id: user_id)
    return unless user
    return if user.welcome_email_sent?

    # send_on_verify: true means wait until email is verified (for email signup)
    # send_on_verify: false means send immediately (for Google OAuth - already verified)
    if send_on_verify && !user.email_verified?
      user.update_columns(welcome_email_pending: true)
      Rails.logger.info "[WelcomeEmailJob] Email pending verification for user #{user_id}"
      return
    end

    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3006')
    Rails.logger.info "[WelcomeEmailJob] Sending welcome email to user #{user_id} at #{user.email}"

    NotificationMailer.notification_email(
      user,
      "Welcome to Warranty Vault! 🎉",
      "Hi #{user.first_name || user.email.split('@').first}, your account is ready. " \
      "Start by uploading your first invoice and we'll track all your warranties automatically.",
      "#{frontend_url}/upload"
    ).deliver_now

    user.update_columns(
      welcome_email_sent_at: Time.current,
      welcome_email_pending: false
    )

    Rails.logger.info "[WelcomeEmailJob] Welcome email sent successfully to user #{user_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[WelcomeEmailJob] User not found: #{user_id}"
  rescue => e
    Rails.logger.error "[WelcomeEmailJob] Failed for user #{user_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
end
