# frozen_string_literal: true

# Background job to clean up old notifications
class NotificationCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform(days = 30)
    Rails.logger.info "[NotificationCleanupJob] Starting notification cleanup (older than #{days} days)"

    # Clean up old notifications
    cleaned_count = NotificationService.cleanup_old_notifications(days)

    Rails.logger.info "[NotificationCleanupJob] Cleaned up #{cleaned_count} old notifications"

    # Log to monitoring
    Rails.logger.info "[NotificationCleanupJob] Notification cleanup completed successfully"
  end
end
