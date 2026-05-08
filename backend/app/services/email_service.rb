# frozen_string_literal: true

# Service for handling all email operations
class EmailService
  class << self
    # Send verification email
    def send_verification_email(user)
      return false unless user&.email

      begin
        # Generate token and save it
        token = VerificationService.generate_verification_token(user)
        VerificationMailer.verification_email(user, token).deliver_now
        Rails.logger.info "[EmailService] Verification email sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send verification email: #{e.message}"
        false
      end
    end

    # Send smart reminder email (replaces daily spam)
    def send_smart_reminder(user)
      return false unless user&.email_verified?

      begin
        NotificationMailer.smart_reminder(user).deliver_now
        Rails.logger.info "[EmailService] Smart reminder sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send smart reminder: #{e.message}"
        false
      end
    end

    # Send app reminder email (smart version)
    def send_smart_app_reminder(user)
      return false unless user&.email_verified?

      begin
        NotificationMailer.smart_reminder(user).deliver_now
        Rails.logger.info "[EmailService] Smart app reminder sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send smart app reminder: #{e.message}"
        false
      end
    end

    # Send warranty expiry notification
    def send_warranty_notification(user, warranties)
      return false if !user&.email_verified? || warranties.empty?

      begin
        warranty = warranties.first
        days_remaining = (warranty.expires_at - Date.current).to_i

        if days_remaining <= 0
          WarrantyMailer.with(user: user, invoice: warranty.invoice_item&.invoice, warranty: warranty).warranty_expired.deliver_now
        else
          WarrantyMailer.with(user: user, invoice: warranty.invoice_item&.invoice, warranty: warranty, days_remaining: days_remaining).warranty_expiring_soon.deliver_now
        end

        Rails.logger.info "[EmailService] Warranty notification sent to #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send warranty notification: #{e.message}"
        false
      end
    end

    # Send welcome email
    def send_welcome_email(user)
      return false unless user&.email
      return false unless user.email_verified?

      Rails.logger.info "[EmailService] Attempting to send welcome email to #{user.email}"
      Rails.logger.info "[EmailService] SMTP configured: #{Rails.application.config.action_mailer.delivery_method}"

      begin
        mail = NotificationMailer.welcome_email(user)
        Rails.logger.info "[EmailService] Welcome mail object created: #{mail.subject}"

        result = mail.deliver_now
        Rails.logger.info "[EmailService] Welcome email sent successfully to #{user.email}"
        Rails.logger.info "[EmailService] Message ID: #{result.message_id}" if result.message_id
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send welcome email: #{e.message}"
        Rails.logger.error "[EmailService] Error class: #{e.class}"
        Rails.logger.error "[EmailService] Backtrace: #{e.backtrace.first(5).join("\n")}"
        false
      end
    end

    # Send invoice upload confirmation email
    def send_invoice_uploaded_email(user, invoice)
      return false unless user&.email
      return false unless user.email_verified?

      Rails.logger.info "[EmailService] Attempting to send invoice email to #{user.email}"
      Rails.logger.info "[EmailService] SMTP configured: #{Rails.application.config.action_mailer.delivery_method}"

      begin
        NotificationMailer.invoice_uploaded(user, invoice).deliver_later
        Rails.logger.info "[EmailService] Invoice upload email enqueued for #{user.email}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send invoice upload email: #{e.message}"
        Rails.logger.error "[EmailService] Error class: #{e.class}"
        Rails.logger.error "[EmailService] Backtrace: #{e.backtrace.first(5).join("\n")}"
        false
      end
    end

    # Handle email delivery failures
    def handle_delivery_failure(email, error)
      Rails.logger.error "[EmailService] Email delivery failed for #{email}: #{error}"

      # Log to monitoring system
      # Could integrate with services like Sentry, Rollbar, etc.

      # Optionally notify admin
      # AdminMailer.delivery_failure_notification(email, error).deliver_later
    end

    # Send notification email (used by NotificationDeliveryService)
    def send_notification_email(user, title, message, product_url = nil)
      return false unless user&.email_verified?

      begin
        NotificationMailer.notification_email(user, title, message, product_url).deliver_now
        Rails.logger.info "[EmailService] Notification email sent to #{user.email}: #{title}"
        true
      rescue => e
        Rails.logger.error "[EmailService] Failed to send notification email: #{e.message}"
        false
      end
    end

    # Check email configuration
    def email_configured?
      Rails.application.config.action_mailer.delivery_method != :test
    end
  end
end
