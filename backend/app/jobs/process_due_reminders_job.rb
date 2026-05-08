# frozen_string_literal: true

# ProcessDueRemindersJob — THE ONLY hourly reminder scheduler.
#
# Runs every hour via Sidekiq-Cron.
# Delegates entirely to NotificationService which owns the logic.
class ProcessDueRemindersJob < ApplicationJob
  queue_as :high_priority

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform
    Rails.logger.info "[ProcessDueRemindersJob] ===== START ====="

    stats = NotificationService.process_due_reminders

    Rails.logger.info(
      "[ProcessDueRemindersJob] ===== DONE ===== " \
      "due=#{stats[:due]} sent=#{stats[:sent]} " \
      "skipped=#{stats[:skipped]} failed=#{stats[:failed]}"
    )
  end
end
