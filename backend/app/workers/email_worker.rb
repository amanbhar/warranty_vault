# frozen_string_literal: true

# EmailWorker — the ONLY place emails are sent.
#
# Called exclusively by NotificationService#email_async:
#   EmailWorker.perform_async(notification_id)
#
# Idempotent: safe to retry; re-sending the same notification_id
# is harmless because mailers are stateless and the DB record
# is the source of truth for what to send.
class EmailWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  def perform(notification_id, options = {})
    options = options.with_indifferent_access

    # Handle verification email type (no notification record)
    if options["email_type"] == "verification" || options[:email_type] == :verification
      user = User.find_by(id: options["user_id"] || options[:user_id])
      return unless user
      VerificationMailer.verification_email(user).deliver_now
      return
    end

    return unless notification_id

    if notification_id.present?
      notification = Notification.find_by(id: notification_id)
      unless notification
        Rails.logger.warn "[EmailWorker] Notification #{notification_id} not found — skipping"
        return
      end
      user = notification.user
      deliver(notification, user)
    elsif options[:user_id].present? && options[:email_type].present?
      user = User.find_by(id: options[:user_id])
      return unless user
      deliver_system_email(user, options[:email_type])
    end
  end

  private

  def deliver_system_email(user, type)
    case type.to_sym
    when :verification
      # Logic from User model / VerificationService
      EmailService.send_verification_email(user)
    when :welcome
      EmailService.send_welcome_email(user)
    end
  end

  def deliver(notification, user)
    type = notification.notification_type.to_s
    case type
    when "invoice_created"
      invoice = find_invoice(notification)
      NotificationMailer.invoice_uploaded(user, invoice).deliver_now if invoice

    when "warranty_expiring", "warranty_expired"
      # Find the specific item from metadata
      item = find_item(notification)
      if item
        warranties = item.item_warranties.to_a
        if warranties.any?
          warranty = warranties.first
          days = warranty&.expires_at ? (warranty.expires_at - Date.current).to_i : 0
          days = [ days, 0 ].max  # never negative
          if days <= 0
            WarrantyMailer.with(user: user, invoice: item.invoice, item: item, warranty: warranty)
                          .warranty_expired.deliver_now
          else
            WarrantyMailer.with(user: user, invoice: item.invoice, item: item, warranty: warranty, days_remaining: days)
                          .warranty_expiring_soon.deliver_now
          end
        end
      end

    when "daily_engagement"
      NotificationMailer.smart_reminder(user).deliver_now

    when "invoice_updated", "product_updated"
      item = find_item(notification)
      product_url = item ? "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{item.invoice.id}" : notification.action_url
      NotificationMailer.notification_email(user, notification.title, notification.message, product_url).deliver_now

    else
      # Generic fallback
      product_url = if notification.notification_type.to_s.in?([ "warranty_expiring", "warranty_expired" ])
                     invoice = find_invoice(notification)
                     invoice ? "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{invoice.id}" : notification.action_url
      else
                     notification.action_url
      end
      NotificationMailer.notification_email(
        user,
        notification.title,
        notification.message,
        product_url
      ).deliver_now
    end

    Rails.logger.info "[EmailWorker] Email delivered for notification #{notification.id}"
  end

  def find_invoice(notification)
    invoice_id = notification.metadata&.dig("invoice_id")
    Invoice.find_by(id: invoice_id) if invoice_id
  end

  def find_item(notification)
    item_id = notification.metadata&.dig("invoice_item_id")
    InvoiceItem.includes(:item_warranties, :invoice).find_by(id: item_id) if item_id
  end
end
