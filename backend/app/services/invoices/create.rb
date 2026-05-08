# frozen_string_literal: true

module Invoices
  class Create
    Result = Struct.new(:success?, :invoice, :error, :details, :code, keyword_init: true) do
      def to_h
        {
          success: success?,
          invoice: invoice,
          error: error,
          details: details,
          code: code,
          message: success? ? "Invoice added successfully" : error
        }
      end
    end

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = PayloadNormalizer.call(params)
    end

    def call
      # Check for duplicate invoice number before attempting to save
      if @params[:invoice_number].present?
        normalized_invoice_number = @params[:invoice_number].to_s.strip.upcase
        existing_invoice = @user.invoices.find_by(invoice_number: normalized_invoice_number)
        if existing_invoice.present?
          return Result.new(
            success?: false,
            invoice: nil,
            error: "Invoice already registered",
            details: [ "An invoice with number #{normalized_invoice_number} already exists in your account" ],
            code: "DUPLICATE_INVOICE"
          )
        end
      end

      invoice = @user.invoices.new(
        invoice_number: @params[:invoice_number],
        purchase_date: @params[:purchase_date],
        seller_name: @params[:seller_name],
        platform_name: @params[:platform_name],
        total_amount: @params[:total_amount],
        raw_ai_data: @params[:raw_ai_data],
        status: :processed,
        ocr_status: :completed
      )

      # Attach invoice file if provided
      if @params[:file].present?
        invoice.original_filename = @params[:file].original_filename
        invoice.file.attach(@params[:file])
      end

      Array(@params[:items]).each do |item_params|
        item = invoice.invoice_items.build(
          product_name: item_params[:product_name],
          brand: item_params[:brand],
          model: item_params[:model],
          price: item_params[:price],
          category: item_params[:category],
          description: item_params[:description],
          specifications: item_params[:specifications] || {}
        )

        # Deduplicate warranties by component_name, keeping the longest duration
        deduplicated_warranties = Array(item_params[:item_warranties])
          .group_by { |w| w[:component_name].to_s.downcase.strip }
          .values
          .map { |group| group.max_by { |w| w[:duration_months].to_i } }

        deduplicated_warranties.each do |warranty_params|
          item.item_warranties.build(
            component_name: warranty_params[:component_name],
            duration_months: warranty_params[:duration_months]
          )
        end
      end
      ActiveRecord::Base.transaction do
        invoice.save!
      end

      # Compute and persist expires_at and warranty_status from item warranties
      compute_warranty_metadata(invoice)


      # Send notification and create reminders via unified NotificationService
      NotificationService.handle_invoice_created(invoice.invoice_items.to_a)

      # Clear user dashboard cache
      CacheService.clear_user_cache(@user.id)

      Result.new(success?: true, invoice: invoice, error: nil, details: nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, invoice: nil, error: "Validation failed", details: e.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique => e
      Result.new(
        success?: false,
        invoice: nil,
        error: "Invoice already registered",
        details: [ "This invoice number already exists in your account" ],
        code: "DUPLICATE_INVOICE"
      )
    rescue ActiveRecord::ActiveRecordError => e
      Result.new(success?: false, invoice: nil, error: "Database error", details: [ e.message ])
    end

    private

    def compute_warranty_metadata(invoice)
      all_warranties = invoice.invoice_items.flat_map(&:item_warranties)
      return if all_warranties.empty?

      computed_status = WarrantyStatusCalculator.invoice_status(invoice.invoice_items)
      enum_status = computed_status == "expiring" ? :expiring_soon : computed_status

      # Use latest expiry so invoice-level metadata remains active if any warranty is still valid.
      latest_expiry = all_warranties.map(&:expires_at).compact.max
      invoice.update_columns(
        expires_at: latest_expiry,
        warranty_status: Invoice.warranty_statuses[enum_status]
      )
    end
  end
end
