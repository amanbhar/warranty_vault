# frozen_string_literal: true

module Invoices
  # Handles complete invoice update including:
  # - Invoice-level field updates
  # - Invoice item updates (by ID, not destroy+recreate)
  # - Warranty updates with expiry recalculation
  # - File replacement (safe purge later)
  # - Warranty metadata recomputation
  # - Warranty reminder rescheduling (after commit)
  # - OCR job triggering (after commit)
  #
  # Usage:
  #   result = Invoices::Update.call(invoice:, params:, file: nil)
  class Update
    Result = Struct.new(:success?, :invoice, :error, :details, :file_replaced, keyword_init: true)

    def self.call(invoice:, params:, file: nil)
      new(invoice:, params:, file:).call
    end

    def initialize(invoice:, params:, file: nil)
      @invoice = invoice
      @params = PayloadNormalizer.call(params)
      @file = file
      @file_replaced = false
      @purchase_date_changed = false
      @warranty_changed = false
    end

    def call
      ActiveRecord::Base.transaction do
        handle_file_replacement
        update_invoice_fields
        update_items_and_warranties
      end

      # These run AFTER transaction commits to avoid
      # enqueuing jobs for rolled-back data
      enqueue_post_update_jobs if @file_replaced

      # Global recalculation and reminder synchronization
      WarrantyRecalculationService.recalculate_invoice(
        @invoice,
        purchase_date_changed: @purchase_date_changed,
        warranty_changed: @warranty_changed
      )

      run_post_update_events

      Result.new(
        success?: true,
        invoice: @invoice,
        error: nil,
        details: nil,
        file_replaced: @file_replaced
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[Invoices::Update] Validation failed for invoice #{@invoice&.id}: #{e.message} - #{e.record.errors.full_messages.join(', ')}"
      Result.new(success?: false, invoice: nil, error: "Validation failed", details: e.record.errors.full_messages)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error "[Invoices::Update] Database error for invoice #{@invoice&.id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      Result.new(success?: false, invoice: nil, error: "Database error", details: [ e.message ])
    rescue => e
      Rails.logger.error "[Invoices::Update] Unexpected error for invoice #{@invoice&.id}: #{e.class} - #{e.message}\n#{e.backtrace.first(10).join("\n")}"
      Result.new(success?: false, invoice: nil, error: "Update failed", details: [ e.message ])
    end

    private

    # Handle file replacement safely
    # Marks old file for purge_later (not immediate purge) to respect transaction boundaries
    def handle_file_replacement
      return unless @file.present?

      # Mark current file for later deletion (after transaction commits)
      if @invoice.file.attached?
        @invoice.file.purge_later
      end

      # Attach new file
      @invoice.original_filename = @file.original_filename
      @invoice.file.attach(@file)
      @invoice.ocr_status = :pending
      @file_replaced = true

      Rails.logger.info "[Invoices::Update] File replaced for invoice #{@invoice.id}"
    end

    # Update invoice-level fields
    def update_invoice_fields
      updates = {
        invoice_number: @params[:invoice_number],
        purchase_date: @params[:purchase_date],
        seller_name: @params[:seller_name],
        platform_name: @params[:platform_name],
        total_amount: @params[:total_amount],
        raw_ai_data: @params[:raw_ai_data]
      }.compact_blank

      # Track if purchase_date actually changed
      if @params[:purchase_date].present? && @invoice.purchase_date.to_s != @params[:purchase_date].to_s
        @purchase_date_changed = true
      end

      @invoice.update!(updates) if updates.present?
    end

    # Update items and warranties
    # Uses ID-based updates instead of destroy_all + recreate
    def update_items_and_warranties
      items = Array(@params[:items])
      return if items.blank?

      # If we have exactly 1 item from normalized flat params and invoice already has items,
      # update the first item instead of destroying and recreating
      if items.length == 1 && items.first[:id].blank? && @invoice.invoice_items.any?
        update_existing_first_item(items.first)
        return
      end

      # Handle _destroy flags for existing items
      items_with_destroy = items.select { |i| i[:_destroy].present? || i[:_destroy] == "1" || i[:_destroy] == true }
      items_with_destroy.each do |item_params|
        next unless item_params[:id].present?
        @invoice.invoice_items.find_by(id: item_params[:id])&.destroy
      end

      # Filter out destroyed items
      items = items.reject { |i| i[:_destroy].present? || i[:_destroy] == "1" || i[:_destroy] == true }

      # Update or create items
      items.each do |item_params|
        if item_params[:id].present?
          update_existing_item(item_params)
        else
          create_new_item(item_params)
        end
      end
    end

    # Update the existing first item (flat params flow from EditProduct.jsx)
    def update_existing_first_item(item_params)
      first_item = @invoice.invoice_items.first
      return unless first_item

      first_item.assign_attributes(
        product_name: item_params[:product_name],
        brand: item_params[:brand],
        model: item_params[:model],
        price: item_params[:price],
        category: item_params[:category],
        description: item_params[:description],
        specifications: item_params[:specifications] || first_item.specifications
      )
      first_item.save!

      update_warranties_for_item(first_item, item_params)
    end

    # Update an existing item by ID
    def update_existing_item(item_params)
      item = @invoice.invoice_items.find_by(id: item_params[:id])
      return unless item

      item.assign_attributes(
        product_name: item_params[:product_name],
        brand: item_params[:brand],
        model: item_params[:model],
        price: item_params[:price],
        category: item_params[:category],
        description: item_params[:description],
        specifications: item_params[:specifications] || item.specifications
      )
      item.save!

      update_warranties_for_item(item, item_params)
    end

    # Create a new item
    def create_new_item(item_params)
      item = @invoice.invoice_items.create!(
        product_name: item_params[:product_name],
        brand: item_params[:brand],
        model: item_params[:model],
        price: item_params[:price],
        category: item_params[:category],
        description: item_params[:description],
        specifications: item_params[:specifications] || {}
      )

      create_warranties_for_item(item, item_params)
    end

    # Update existing warranties for an item
    def update_warranties_for_item(item, item_params)
      # Support both warranties (from frontend) and item_warranties (standard)
      warranties = Array(item_params[:warranties] || item_params[:item_warranties])
      return if warranties.blank?

      # Handle _destroy flags
      warranties_with_destroy = warranties.select { |w| w[:_destroy].present? || w[:_destroy] == "1" || w[:_destroy] == true }
      warranties_with_destroy.each do |warranty_params|
        next unless warranty_params[:id].present?
        item.item_warranties.find_by(id: warranty_params[:id])&.destroy
      end

      # Filter out destroyed warranties
      warranties = warranties.reject { |w| w[:_destroy].present? || w[:_destroy] == "1" || w[:_destroy] == true }

      # Deduplicate by component_name, keeping longest duration
      deduplicated = warranties
        .group_by { |w| w[:component_name].to_s.downcase.strip }
        .values
        .map { |group| group.max_by { |w| w[:duration_months].to_i } }

      deduplicated.each do |warranty_params|
        component = warranty_params[:component_name].to_s.downcase.strip

        warranty = if warranty_params[:id].present?
          # Find by ID if provided - this is the PRIMARY way to identify existing warranties
          found = item.item_warranties.find_by(id: warranty_params[:id])
          if found
            # Update component name if it changed
            if found.component_name != component
              found.component_name = component
            end
          end
          found
        else
          # Fall back to matching by component_name (ID may be lost during normalization)
          found = item.item_warranties.find_by(component_name: component)
          found
        end

        if warranty
          # Update existing warranty
          update_warranty_duration!(warranty, warranty_params[:duration_months])
        else
          # For legacy top-level warranty_duration updates, prefer updating the
          # existing single warranty instead of creating "main_unit" duplicates.
          if legacy_warranty_duration?(warranty_params)
            if item.item_warranties.count == 1
              update_warranty_duration!(item.item_warranties.first, warranty_params[:duration_months])
            elsif item.item_warranties.none?
              item.item_warranties.create!(
                component_name: component,
                duration_months: warranty_params[:duration_months]
              )
            end
          else
            # Create new warranty only if no existing match found
            item.item_warranties.create!(
              component_name: component,
              duration_months: warranty_params[:duration_months]
            )
          end
        end
      end
    end

    # Create warranties for a new item
    def create_warranties_for_item(item, item_params)
      # Support both warranties (from frontend) and item_warranties (standard)
      warranties = Array(item_params[:warranties] || item_params[:item_warranties])
      return if warranties.blank?

      # Deduplicate by component_name, keeping longest duration
      deduplicated = warranties
        .group_by { |w| w[:component_name].to_s.downcase.strip }
        .values
        .map { |group| group.max_by { |w| w[:duration_months].to_i } }

      deduplicated.each do |warranty_params|
        item.item_warranties.create!(
          component_name: warranty_params[:component_name],
          duration_months: warranty_params[:duration_months]
        )
      end
    end


    # Enqueue OCR job AFTER transaction commits
    def enqueue_post_update_jobs
      InvoiceOcrJob.perform_later(@invoice.id)
      Rails.logger.info "[Invoices::Update] Enqueued OCR job for invoice #{@invoice.id}"
    end

    def update_warranty_duration!(warranty, duration_months)
      @warranty_changed = true if warranty.duration_months != duration_months
      warranty.duration_months = duration_months
      warranty.calculate_expires_at
      warranty.save!(validate: false)
    end

    def legacy_warranty_duration?(warranty_params)
      value = warranty_params[:legacy_warranty_duration]
      value == true || value == "true" || value == "1" || value == 1
    end

    def run_post_update_events
      user  = @invoice.user
      items = @invoice.invoice_items.includes(:item_warranties)

      if @purchase_date_changed
        items.each { |item| NotificationService.handle_warranty_update(item, reason: :purchase_date_changed) }
      elsif @warranty_changed
        items.each { |item| NotificationService.handle_warranty_update(item, reason: :warranty_changed) }
      else
        # No scheduling-relevant change — just sync reminders silently (no confirmation notification)
        items.each { |item| NotificationService.handle_warranty_update(item) }
      end

      CacheService.clear_user_cache(user.id)
    end
  end
end
