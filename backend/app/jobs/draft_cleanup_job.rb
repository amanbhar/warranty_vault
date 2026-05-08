# frozen_string_literal: true

# Job to clean up old draft invoices
# Runs daily to remove draft invoices that were never finalized
class DraftCleanupJob < ApplicationJob
  queue_as :default

  # Clean up draft invoices older than specified days
  # Default: 7 days (can be configured via environment variable)
  def perform(days_old = nil)
    # Get days from environment or use default
    days_old = days_old || ENV.fetch("DRAFT_CLEANUP_DAYS", 7).to_i
    Rails.logger.info "[DraftCleanupJob] Starting cleanup of draft invoices older than #{days_old} days"

    # Find all draft invoices older than cutoff using scope
    old_drafts = Invoice.old_drafts(days_old)

    if old_drafts.exists?
      count = old_drafts.count
      Rails.logger.info "[DraftCleanupJob] Found #{count} draft invoices to clean up"

      # Log details before deletion for audit
      old_drafts.find_each do |invoice|
        Rails.logger.info "[DraftCleanupJob] Deleting draft invoice: #{invoice.id} - #{invoice.product_name} (created: #{invoice.created_at})"

        # Also delete any associated files
        if invoice.file.attached?
          invoice.file.purge
          Rails.logger.info "[DraftCleanupJob] Deleted file for invoice #{invoice.id}"
        end
      end

      # Bulk delete for efficiency
      old_drafts.delete_all

      Rails.logger.info "[DraftCleanupJob] Successfully deleted #{count} old draft invoices"
    else
      Rails.logger.info "[DraftCleanupJob] No old draft invoices found"
    end

    # Report summary
    total_drafts_remaining = Invoice.draft.count
    Rails.logger.info "[DraftCleanupJob] Cleanup complete. #{total_drafts_remaining} draft invoices remaining"
  end
end
