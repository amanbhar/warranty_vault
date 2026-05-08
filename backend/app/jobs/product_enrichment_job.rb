# frozen_string_literal: true

# Product Enrichment Job - Async product image assignment
#
# Purpose:
# - Decouples product image assignment from OCR processing
# - Runs asynchronously after OCR completes successfully
# - No external API calls - uses local image mapping
# - Low priority queue to avoid blocking critical jobs
#
# Processing time: < 1 second (local mapping only)
class ProductEnrichmentJob < ApplicationJob
  queue_as :low_priority

  # Retry configuration
  retry_on StandardError, wait: ->(attempts) { attempts * 10 }, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(invoice_id)
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice

    Rails.logger.info "[ProductEnrichmentJob] Starting product enrichment for invoice #{invoice_id}"

    # Skip if already enriched
    if invoice.product_image_url.present?
      Rails.logger.info "[ProductEnrichmentJob] Invoice #{invoice_id} already has product image, skipping"
      return
    end

    start_time = Time.current

    # Assign default product image based on category detection
    ProductImageService.fetch_for_invoice(invoice)

    Rails.logger.info "[ProductEnrichmentJob] Completed enrichment for invoice #{invoice_id} (#{Time.current - start_time}s)"
  end
end
