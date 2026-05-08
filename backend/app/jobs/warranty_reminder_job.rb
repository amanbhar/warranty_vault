# frozen_string_literal: true

# Background job to send warranty expiration reminders
# Scheduled to run 30 days before warranty expiry
#
# Usage:
#   WarrantyReminderJob.perform_later(warranty_id)
#   WarrantyReminderJob.set(wait_until: date).perform_later(warranty_id)
class WarrantyReminderJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on ActiveRecord::RecordNotFound, wait: :exponentially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  # Sidekiq unique jobs requires sidekiq-unique-jobs gem
  # For now, we rely on the reminder_sent flag for idempotency

  def perform(warranty_id, milestone = "thirty_days")
    Rails.logger.info "[NOTIFICATION_TRIGGER] #{Time.current} - WarrantyReminderJob perform - Warranty: #{warranty_id}, Milestone: #{milestone}"
    warranty = find_warranty(warranty_id)
    return unless warranty

    user = warranty_user(warranty)
    return unless user

    # Use centralized service for idempotent notification
    CentralizedNotificationService.notify_warranty_expiring(user, [ warranty ], milestone: milestone)

    # Broadcast real-time update
    WarrantyBroadcastService.broadcast_warranty_expiry_alert(warranty)
    Rails.logger.info "[WarrantyReminderJob] Reminder processed for warranty #{warranty_id} at #{milestone}"
  rescue => e
    Rails.logger.error "[WarrantyReminderJob] Error processing warranty #{warranty_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  # Find warranty with proper error handling
  # Supports both legacy ProductWarranty and new ItemWarranty
  def find_warranty(warranty_id)
    ItemWarranty.find_by(id: warranty_id) || ProductWarranty.find_by(id: warranty_id)
  rescue => e
    Rails.logger.error "[WarrantyReminderJob] Error finding warranty #{warranty_id}: #{e.message}"
    nil
  end

  # Get user from warranty - handles both ItemWarranty and ProductWarranty paths
  def warranty_user(warranty)
    if warranty.is_a?(ItemWarranty)
      warranty.invoice_item&.invoice&.user
    else
      warranty.invoice&.user
    end
  end
end
