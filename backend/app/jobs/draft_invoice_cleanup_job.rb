# frozen_string_literal: true

# DraftInvoiceCleanupJob
#
# Purges invoice records that are still in :draft or :failed status and were
# created more than 30 minutes ago.  These are orphaned records left behind by:
#
#   • users who clicked "Go Back" before the frontend called DELETE /cancel
#   • network errors that prevented the cancel request from reaching the server
#   • OCR jobs that failed and whose invoice was never explicitly removed
#
# The job is deliberately conservative:
#   - It NEVER touches :processed invoices.
#   - It destroys records in small batches (find_each) to avoid locking.
#   - Individual destroy failures are rescued and logged so one bad record
#     cannot prevent the rest from being cleaned up.
#
# Scheduled to run every 30 minutes via sidekiq-scheduler (see
# config/initializers/sidekiq_scheduler.rb).
class DraftInvoiceCleanupJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 30.minutes

  def perform
    cutoff = STALE_AFTER.ago
    scope  = Invoice.where(status: [ Invoice.statuses[:draft], Invoice.statuses[:failed] ])
                    .where("created_at < ?", cutoff)

    count = 0

    scope.find_each do |invoice|
      # Safety guard – never touch processed invoices regardless of scope bugs
      next if invoice.processed?

      invoice.destroy!
      count += 1
    rescue => e
      Rails.logger.error "[DraftInvoiceCleanupJob] Failed to destroy invoice #{invoice.id}: #{e.message}"
    end

    Rails.logger.info "[DraftInvoiceCleanupJob] Cleaned up #{count} stale draft/failed invoices older than #{STALE_AFTER / 60} minutes"
  end
end
