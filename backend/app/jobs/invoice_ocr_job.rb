# frozen_string_literal: true

# Invoice OCR Job - AI Service Manager Integration
#
# Features:
# 1. Uses configurable AI service manager
# 2. Automatic fallback between Gemini and OpenAI
# 3. Robust error handling and logging
# 4. Comprehensive data validation
# 5. Warranty parsing and storage
# 6. Fallback mechanisms
#
# Processing time: 5-15 seconds
class InvoiceOcrJob < ApplicationJob
  queue_as :high_priority

  # Retry configuration - reduced attempts for faster failure
  # Total max retries: 2 (Gemini) + 2 (OpenAI) + 1 (Timeout) = 5 attempts max
  retry_on GeminiInvoiceScanner::GeminiError, wait: ->(attempts) { attempts * 3 }, attempts: 2
  retry_on OpenAiInvoiceScanner::OpenAiError, wait: ->(attempts) { attempts * 3 }, attempts: 2
  retry_on AiServiceManager::ServiceError, wait: ->(attempts) { attempts * 3 }, attempts: 2
  retry_on Timeout::Error, wait: 5.seconds, attempts: 1

  discard_on ActiveRecord::RecordNotFound

  def perform(invoice_id)
    start_time = Time.current
    invoice = Invoice.find_by(id: invoice_id)
    return unless invoice

    primary_service = ENV.fetch("PRIMARY_AI_SERVICE", "gemini")
    fallback_service = ENV.fetch("FALLBACK_AI_SERVICE", "openai")

    Rails.logger.info "[InvoiceOcrJob] Starting AI processing for invoice #{invoice_id}"
    Rails.logger.info "[InvoiceOcrJob] Primary AI service: #{primary_service}"
    Rails.logger.info "[InvoiceOcrJob] Fallback AI service: #{fallback_service}"

    # Update status
    invoice.update_columns(ocr_status: :processing)

    begin
      # Process with AI Service Manager (handles fallback automatically)
      # Timeout: 35s = 30s (AI service) + 5s buffer
      result = Timeout.timeout(35) do
        AiServiceManager.process_invoice(invoice)
      end

      # Handle results
      if result[:success]
        Rails.logger.info "[InvoiceOcrJob] Success for invoice #{invoice_id} (#{Time.current - start_time}s)"
        Rails.logger.info "[InvoiceOcrJob] AI service used: #{result[:ai_service] || 'unknown'}"

        # Post-processing
        schedule_post_processing(invoice)
      else
        Rails.logger.warn "[InvoiceOcrJob] Failed for invoice #{invoice_id}: #{result[:error]}"
        handle_processing_failure(invoice, result[:error])
      end

      result
    rescue Timeout::Error
      Rails.logger.error "[InvoiceOcrJob] Timeout for invoice #{invoice_id} after 35s"
      handle_processing_failure(invoice, "Processing timeout after 35 seconds")
      { success: false, error: "Timeout after 35 seconds" }
    rescue => e
      Rails.logger.error "[InvoiceOcrJob] Error for invoice #{invoice_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      handle_processing_failure(invoice, e.message)
      { success: false, error: e.message }
    end
  end

  private

  # Process invoice with AI Service Manager
  def process_with_ai_manager(invoice)
    Rails.logger.info "[InvoiceOcrJob] Using AI Service Manager for invoice #{invoice.id}"

    result = AiServiceManager.process_invoice(invoice)

    # Add service information to result
    if result[:success]
      result[:ai_service] = ENV.fetch("PRIMARY_AI_SERVICE", "gemini")
      result[:ai_model] = get_current_ai_model
    end

    result
  end

  # Handle processing failure
  def handle_processing_failure(invoice, error_message)
    if invoice.draft?
      user = invoice.user
      invoice.destroy
      Notification.ocr_failed_notification(user, invoice, error_message)
    else
      invoice.update_columns(
        ocr_status: :failed,
        ocr_error_message: error_message
      )

      # Send notification
      Notification.ocr_failed_notification(invoice.user, invoice, error_message)
    end
  end

  # Schedule post-processing
  def schedule_post_processing(invoice)
    # Update invoice status to processed (if still draft)
    if invoice.draft?
      invoice.update_columns(status: :processed)
    end

    # Send in-app notification
    Notification.ocr_complete_notification(invoice.user, invoice)

    # Send email notification with complete OCR data
    EmailService.send_invoice_uploaded_email(invoice.user, invoice)

    # Product enrichment - async, low priority (no external API calls)
    ProductEnrichmentJob.perform_later(invoice)
  end

  # Get current AI model being used
  def get_current_ai_model
    service = ENV.fetch("PRIMARY_AI_SERVICE", "gemini")

    case service
    when "gemini"
      ENV.fetch("GEMINI_MODEL", "gemini-1.5-flash")
    when "openai"
      ENV.fetch("OPENAI_MODEL", "gpt-4o-mini")
    else
      "unknown"
    end
  end
end
