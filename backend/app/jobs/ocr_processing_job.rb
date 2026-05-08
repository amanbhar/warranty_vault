class OcrProcessingJob < ApplicationJob
  queue_as :default

  # Retry on failure but don't block the queue
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(invoice_id)
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice

    Rails.logger.info "[OcrProcessingJob] Starting OCR processing for invoice #{invoice_id}"

    # Update status to processing
    invoice.update_columns(ocr_status: :processing)

    # Process the invoice with OCR
    result = OcrService.new(invoice).process

    # Handle results
    if result[:success]
      Rails.logger.info "[OcrProcessingJob] OCR successful for invoice #{invoice_id}"
      Notification.ocr_complete_notification(invoice.user, invoice)
    else
      Rails.logger.warn "[OcrProcessingJob] OCR failed for invoice #{invoice_id}: #{result[:error]}"
      Notification.ocr_failed_notification(invoice.user, invoice, result[:error])
    end

    Rails.logger.info "[OcrProcessingJob] OCR processing complete for invoice #{invoice_id}"

    result
  end
end
