# frozen_string_literal: true

module Api
  module V1
    class InvoiceScansController < ApplicationController
      # POST /api/v1/invoice_scans/scan
      # Scan invoice file with AI and return extracted data (no DB record created)
      # This is the FIRST step in the scan-then-confirm flow
      def scan
        Rails.logger.info "[InvoiceScansController#scan] Starting scan for file: #{params[:file]&.original_filename}"

        unless params[:file].present?
          return render json: {
            success: false,
            error: {
              code: "NO_FILE_PROVIDED",
              message: "No invoice file provided",
              user_message: "Please select an invoice file to upload",
              suggestion: "Click the upload button and select your invoice PDF or image",
              allow_manual_entry: true
            }
          }, status: :unprocessable_entity
        end

        file = params[:file]
        # Validate file type
        unless valid_invoice_file?(file)
          return render json: {
            success: false,
            error: {
              code: "INVALID_FILE_TYPE",
              message: "Invalid file type: #{file.content_type}",
              user_message: "Unsupported file format",
              suggestion: "Please upload a PDF, PNG, JPG, or JPEG file",
              accepted_formats: [ "PDF", "PNG", "JPG", "JPEG" ],
              allow_manual_entry: true
            }
          }, status: :unprocessable_entity
        end

        # Validate file size (max 10MB)
        if file.size > 10.megabytes
          return render json: {
            success: false,
            error: {
              code: "FILE_TOO_LARGE",
              message: "File size: #{(file.size / 1.megabyte).round(2)}MB exceeds limit",
              user_message: "File is too large",
              suggestion: "Please upload a file smaller than 10MB",
              max_size: "10MB",
              current_size: "#{(file.size / 1.megabyte).round(2)}MB",
              allow_manual_entry: true
            }
          }, status: :unprocessable_entity
        end

        # Use InvoiceScanService for extraction (NO DB writes)
        result = InvoiceScanService.scan_file(file)

        if result[:success]
          Rails.logger.info "[InvoiceScansController#scan] Scan successful"

          render json: {
            success: true,
            message: result[:message],
            data: result[:data],
            warnings: result[:warnings] || Array(result[:warning]).compact,
            confidence_score: result[:confidence_score],
            scan_duration_ms: result[:scan_duration_ms]
          }
        else
          error_payload = result[:error].is_a?(Hash) ? result[:error] : {
            code: "SCAN_FAILED",
            message: result[:error].to_s,
            user_message: "Unable to process invoice. Please upload a clearer image.",
            suggestion: "Ensure the invoice is well-lit and all text is visible",
            allow_manual_entry: true,
            retry_allowed: true
          }

          Rails.logger.error "[InvoiceScansController#scan] Scan failed: #{error_payload[:message]}"

          # Return structured error response for frontend
          render json: {
            success: false,
            error: error_payload
          }, status: :unprocessable_entity
        end
      end

      private

      # Validate invoice file type
      def valid_invoice_file?(file)
        return false unless file.present?

        valid_types = [
          "application/pdf",
          "image/png",
          "image/jpeg",
          "image/jpg"
        ]

        # Check content type
        content_type = file.content_type.to_s.downcase
        valid_types.include?(content_type) ||
          content_type.include?("pdf") ||
          content_type.include?("image")
      end
    end
  end
end
