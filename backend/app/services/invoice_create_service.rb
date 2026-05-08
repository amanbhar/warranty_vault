# frozen_string_literal: true

# Invoice Create Service - Delegates to normalized Invoices::Create
#
# Purpose:
# - Creates invoice ONLY after user has validated/edited scanned data
# - Enforces warranty validation (rejects or requires confirmation if missing)
# - Triggers notifications after successful creation
#
# Usage:
#   result = InvoiceCreateService.create(user: user, params: params)
#   if result[:success]
#     # invoice created, notifications sent
#   else
#     # handle errors
#   end
class InvoiceCreateService
  class ValidationError < StandardError; end
  class WarrantyValidationError < StandardError; end

  def self.create(user:, params:)
    new(user: user, params: params).create
  end

  def initialize(user:, params:)
    @user = user
    @params = normalize_params(params)
  end

  def create
    result = Invoices::Create.call(user: @user, params: @params)

    # Notification handled by Invoices::Create via NotificationServiceV2
    result.to_h
  rescue => e
    Rails.logger.error "[InvoiceCreateService] Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    {
      success: false,
      error: {
        code: "INTERNAL_ERROR",
        message: "Failed to create invoice"
      }
    }
  end

  private

  def normalize_params(raw_params)
    hash = raw_params.respond_to?(:to_unsafe_h) ? raw_params.to_unsafe_h : raw_params.to_h
    hash = hash.deep_symbolize_keys
    hash
  end
end
