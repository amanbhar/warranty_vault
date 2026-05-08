module Api
  module V1
    class InvoicesController < ApplicationController
      before_action :set_invoice, only: [ :show, :update, :destroy, :download, :preview, :retry_ocr, :finalize, :ocr_status, :cancel ]

      # GET /api/v1/invoices
      def index
        invoices = Invoices::Query.new(
          scope: current_user.invoices.includes(invoice_items: :item_warranties),
          params: params
        ).call

        paginated_invoices, pagination = paginate(invoices)

        render json: {
          invoices: InvoiceSerializer.render_collection(paginated_invoices, include_warranties: true),
          pagination: pagination
        }
      end

      # GET /api/v1/invoices/:id
      def show
        render json: InvoiceSerializer.render(@invoice, include_warranties: true)
      end

      # POST /api/v1/invoices
      # Create invoice after user confirms scanned data
      # Also supports direct upload (creates as draft if required fields missing)
      def create
        payload = params.key?(:invoice) ? params[:invoice] : params
        payload_keys = if payload.respond_to?(:to_unsafe_h)
                         payload.to_unsafe_h.keys
        elsif payload.respond_to?(:to_h)
                         payload.to_h.keys
        else
                         []
        end
        Rails.logger.info "[InvoicesController#create] create request received (keys=#{payload_keys.sort.join(',')})"

        invoice_payload = payload
        extracted_data = invoice_payload[:extracted_data]
        extracted_data = JSON.parse(extracted_data) rescue extracted_data if extracted_data.is_a?(String)

        # Support both flat and namespaced (invoice[...]) FormData submissions
        p = invoice_payload

        # Determine if this is a confirmed upload (has required fields) or needs review
        extracted_first_item = if extracted_data.is_a?(Hash)
                                 items = extracted_data["items"] || extracted_data[:items]
                                 items.is_a?(Array) ? items.first : extracted_data
        end
        has_required_fields = (
          p[:purchase_date].present? || extracted_data&.[]("purchase_date").present? || extracted_data&.[](:purchase_date).present?
        ) && (
          p[:product_name].present? || extracted_data&.[]("product_name").present? || extracted_data&.[](:product_name).present? || extracted_first_item&.[]("product_name").present? || extracted_first_item&.[](:product_name).present?
        ) && (
          p[:brand].present? || extracted_data&.[]("brand").present? || extracted_data&.[](:brand).present? || extracted_first_item&.[]("brand").present? || extracted_first_item&.[](:brand).present?
        )

        if has_required_fields
          create_with_service
        else
          missing = []
          missing << "product_name" if p[:product_name].blank? && extracted_data&.[]("product_name").blank? && extracted_data&.[](:product_name).blank? && extracted_first_item&.[]("product_name").blank? && extracted_first_item&.[](:product_name).blank?
          missing << "brand"        if p[:brand].blank? && extracted_data&.[]("brand").blank? && extracted_data&.[](:brand).blank? && extracted_first_item&.[]("brand").blank? && extracted_first_item&.[](:brand).blank?
          missing << "purchase_date" if p[:purchase_date].blank? && extracted_data&.[]("purchase_date").blank? && extracted_data&.[](:purchase_date).blank?
          render json: { success: false, error: "Missing required fields: #{missing.join(', ')}" }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/invoices/scan_upload (Stateless Extraction)
      def scan_upload
        file = params[:file]
        return render json: { error: "No invoice file provided", success: false }, status: :bad_request unless file

        # Send directly to the refactored Service for scanning (NO DB SAVING)
        result = InvoiceScanService.process_file_stateless(file)

        if result[:success]
          extracted_data = result[:data]
          warnings = result[:warnings] || []
          missing_fields = result[:missing_fields] || []

          render json: {
            success: true,
            message: "Scan successful. Please review the details.",
            invoice: extracted_data,
            warnings: warnings,
            missing_fields: missing_fields,
            confidence_score: result[:confidence_score]
          }, status: :ok
        else
          # If scanning fails entirely, prompt manual entry with details
          error_msg = result[:error] || "AI Scanner failed to extract content."
          full_error = "#{error_msg} If the image is blurry, please try re-uploading. Otherwise, you can enter details manually below."

          render json: {
            success: false,
            error: full_error,
            details: result[:error],
            missing_fields: result.dig(:error, :missing_fields) || []
          }, status: :unprocessable_entity
        end
      end

      # Create invoice using InvoiceCreateService (recommended flow)
      # Ensures proper validation, duplicate checking, and notification handling
      def create_with_service
        # Normalize nested JSON strings from FormData
        parsed_params = create_params.to_unsafe_h.deep_symbolize_keys

        if parsed_params[:raw_ai_data].is_a?(String)
          parsed_params[:raw_ai_data] = JSON.parse(parsed_params[:raw_ai_data]) rescue {}
        end

        if parsed_params[:items].present?
          items_list = parsed_params[:items].is_a?(Hash) ? parsed_params[:items].values : parsed_params[:items]
          items_list.each do |item|
            if item[:specifications].is_a?(String)
              item[:specifications] = JSON.parse(item[:specifications]) rescue {}
            end
          end
        end
        result = InvoiceCreateService.create(
          user: current_user,
          params: parsed_params
        )

        if result[:success]
          render json: {
            success: true,
            invoice: InvoiceSerializer.render(result[:invoice], include_warranties: true),
            message: result[:message]
          }, status: :created
        else
          error = result[:error]
          http_status = :unprocessable_entity

          # Handle duplicate invoice with specific error code and message
          if error.is_a?(Hash) && error[:code] == "DUPLICATE_INVOICE"
            render json: {
              success: false,
              error: error[:message] || "Invoice already registered",
              details: error[:details],
              code: "DUPLICATE_INVOICE"
            }, status: :conflict
            return
          end

          error_message = if error.is_a?(Hash) && error[:details].present?
                            error[:details].join(", ")
          elsif error.is_a?(String)
                            error
          elsif error.is_a?(Hash)
                            error[:message] || "Unknown error"
          else
                            "Unknown error"
          end

          render json: {
            success: false,
            error: error_message,
            code: error.is_a?(Hash) ? error[:code] : nil
          }, status: http_status
        end
      end

      # Create confirmed invoice with transaction safety
      # ALL database operations are wrapped in a transaction for atomicity
      def create_confirmed_invoice
        @invoice = nil

        begin
          ActiveRecord::Base.transaction do
            @invoice = current_user.invoices.new(invoice_params)

            # Handle invoice file upload
            if params[:file].present?
              @invoice.original_filename = params[:file].original_filename
              @invoice.file.attach(params[:file])
            end

            # Handle product image upload (optional)
            if params[:product_image].present?
              @invoice.product_image.attach(params[:product_image])
            end

            # Set status to processed (user confirmed data)
            @invoice.status = :processed
            @invoice.ocr_status = :completed

            # Validate and save - will fail if required fields missing or invalid
            # Debug logging to track params
            Rails.logger.info "[INVOICE UPDATE] Params: #{params[:invoice].to_unsafe_h}"
            @invoice.update!(invoice_params)
          end

          # Transaction will rollback if any of the above fails

          render json: {
            invoice: invoice_data(@invoice, include_warranties: true),
            message: "Invoice created successfully"
          }, status: :created

        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "[InvoicesController#create] Validation failed: #{e.message}"
          render json: {
            error: "Validation failed",
            details: e.record.errors.full_messages
          }, status: :unprocessable_entity
        rescue ActiveRecord::ActiveRecordError => e
          Rails.logger.error "[InvoicesController#create] Database error: #{e.message}"
          render json: {
            error: "Failed to create invoice",
            details: e.message
          }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error "[InvoicesController#create] Unexpected error: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: {
            error: "Failed to create invoice",
            details: e.message
          }, status: :unprocessable_entity
        end
      end

      # Create draft invoice for manual review flow
      def create_draft_invoice
        @invoice = current_user.invoices.new(invoice_params)

        # Handle invoice file upload
        if params[:file].present?
          @invoice.original_filename = params[:file].original_filename
          @invoice.file.attach(params[:file])
        end

        # Handle product image upload (optional)
        if params[:product_image].present?
          @invoice.product_image.attach(params[:product_image])
        end

        # Set a temporary product name if not provided
        @invoice.product_name ||= params[:file].present? ? params[:file].original_filename.to_s.sub(/\.[^.]+\z/, "").humanize : "Unknown Product"

        # Set as draft - requires review before processing
        @invoice.status = :draft
        @invoice.ocr_status = :pending

        if @invoice.save
          # Trigger OCR in background to populate fields
          InvoiceOcrJob.perform_later(@invoice.id)

          render json: {
            invoice: invoice_data(@invoice),
            message: "Invoice uploaded. Please review and confirm the details.",
            requires_review: true
          }, status: :created
        else
          Rails.logger.error "[InvoicesController#create] Draft validation failed: #{@invoice.errors.full_messages.join(', ')}"
          render json: {
            error: "Upload failed",
            details: @invoice.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/invoices/:id
      def update
        # Pass all params (root + nested) to the service
        # PayloadNormalizer handles both flat and nested formats
        result = Invoices::Update.call(
          invoice: @invoice,
          params: permitted_update_params,
          file: params[:file] || params.dig(:invoice, :file)
        )

        if result.success?
          render json: {
            success: true,
            invoice: InvoiceSerializer.render(result.invoice, include_warranties: true),
            message: "Invoice updated successfully"
          }
        else
          render json: { success: false, error: result.details&.join(", ") || result.error }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/invoices/:id
      def destroy
        user_id = @invoice.user_id
        @invoice.destroy!

        # Clear user dashboard cache
        CacheService.clear_user_cache(user_id)

        render json: { message: "Invoice deleted successfully" }
      end

      # GET /api/v1/invoices/:id/download
      def download
        if @invoice.file.attached?
          blob = @invoice.file.blob

          # Use send_data for API controllers (send_blob is for full Rails)
          send_data blob.download,
            filename: blob.filename.to_s,
            type: blob.content_type,
            disposition: "attachment"
        else
          render json: { error: "No file attached" }, status: :not_found
        end
      end

      # GET /api/v1/invoices/:id/preview
      # View invoice in browser (PDF viewer or image display)
      # Uses redirect to Active Storage URL so auth is handled and no blocking
      def preview
        if @invoice.file.attached?
          file_url = Rails.application.routes.url_helpers.rails_blob_url(
            @invoice.file,
            only_path: true,
            disposition: "inline"
          )
          redirect_to file_url, allow_other_host: true
        else
          render json: { error: "No file attached" }, status: :not_found
        end
      end

      # GET /api/v1/invoices/stats
      def stats
        invoices = current_user.invoices.processed
        items = InvoiceItem.joins(:invoice)
          .includes(:item_warranties)
          .where(invoices: { user_id: current_user.id, status: :processed })
        item_status_counts = WarrantyStatusCalculator.count_product_statuses(items)

        stats = {
          total: invoices.count,
          active: item_status_counts[:active],
          expiring_soon: item_status_counts[:expiring],
          expired: item_status_counts[:expired],
          total_value: invoices.sum(:total_amount).to_f || 0
        }

        render json: { stats: stats }
      end

      # GET /api/v1/dashboard
      # Comprehensive dashboard data with warranty breakdown
      def dashboard
        data = Invoices::DashboardQuery.new(user: current_user).call

        render json: {
          dashboard: {
            summary: data[:summary],
            upcoming_expirations: data[:upcoming_expirations],
            recent_invoices: InvoiceSerializer.render_collection(data[:recent_invoices])
          }
        }
      rescue => e
        Rails.logger.error "[Dashboard] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: "Failed to load dashboard data", details: e.message }, status: :internal_server_error
      end

      # GET /api/v1/invoices/export
      # Export all user's invoices as a single ZIP file
      def export
        begin
          zip_file = Invoices::ExportService.call(current_user)

          # Read the file content
          file_content = File.read(zip_file.path)
          filename = "invoices_#{Date.today}.zip"

          # Send data with proper headers for CORS
          send_data(
            file_content,
            type: "application/zip",
            disposition: "attachment; filename=\"#{filename}\"",
            filename: filename
          )
        rescue => e
          Rails.logger.error "[InvoicesController#export] Error: #{e.message}"
          render json: { error: "Failed to export invoices" }, status: :internal_server_error
        ensure
          zip_file&.unlink  # Clean up temp file
        end
      end

      # POST /api/v1/invoices/:id/retry_ocr
      def retry_ocr
        unless @invoice.file.attached?
          return render json: { error: "No file attached for OCR" }, status: :unprocessable_entity
        end

        @invoice.update(ocr_status: :pending, ocr_error_message: nil)
        InvoiceOcrJob.perform_later(@invoice.id)

        render json: {
          message: "OCR processing restarted",
          ocr_status: @invoice.ocr_status
        }
      end

      # POST /api/v1/invoices/:id/finalize
      # Finalize invoice - used for manual entry flow (transition from draft to processed)
      def finalize
        # Only allow draft invoices to be finalized
        unless @invoice.draft?
          return render json: { error: "Invoice has already been processed" }, status: :unprocessable_entity
        end

        # Update invoice with confirmed data
        if @invoice.update(invoice_params)
          @invoice.update_columns(status: :processed, ocr_status: :completed)
          # Notification handled by service layer

          render json: {
            invoice: invoice_data(@invoice),
            message: "Invoice confirmed successfully"
          }
        else
          render json: { error: @invoice.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/invoices/:id/ocr_status
      def ocr_status
        # Calculate processing time if invoice was recently created
        processing_time = nil
        if @invoice.created_at.present?
          processing_time = Time.current - @invoice.created_at
        end

        render json: {
          invoice_id: @invoice.id,
          ocr_status: @invoice.ocr_status,
          ocr_error_message: @invoice.ocr_error_message,
          ocr_data: @invoice.ocr_data_hash,
          processing_time_seconds: processing_time&.round(2),
          estimated_completion: estimate_completion_time(@invoice),
          extracted_fields: {
            product_name: @invoice.product_name,
            brand: @invoice.brand,
            seller: @invoice.seller,
            amount: @invoice.total_amount,
            purchase_date: @invoice.purchase_date,
            warranty_duration: @invoice.warranty_duration
          }
        }
      end

      # DELETE /api/v1/invoices/:id/cancel
      # Cancel invoice upload and destroy draft record
      def cancel
        # Only allow draft invoices to be cancelled
        if @invoice.draft?
          user_id = @invoice.user_id
          # Destroy the draft invoice
          @invoice.destroy!

          # Clear user dashboard cache
          CacheService.clear_user_cache(user_id)

          render json: {
            message: "Invoice upload cancelled and removed successfully"
          }
        else
          # For processed invoices, just return success (already saved)
          render json: {
            message: "Invoice cancelled successfully"
          }
        end
      end

      private

      def set_invoice
        @invoice = current_user.invoices
          .includes(invoice_items: :item_warranties)
          .find_by(id: params[:id])
        return if @invoice

        render json: { error: "Invoice not found" }, status: :not_found
      end

      def invoice_params
        # Handle both wrapped (JSON) and flat (FormData) params
        p = params.key?(:invoice) ? params.require(:invoice) : params
        permitted = p.permit(:product_name, :brand, :model_number, :seller, :amount, :total_amount, :purchase_date,
                             :invoice_number, :warranty_duration, :category, :file, :product_image, :ocr_status)
        permitted[:total_amount] ||= permitted.delete(:amount) if permitted[:total_amount].blank? && permitted[:amount].present?
        permitted
      end

      # Permitted params for InvoiceCreateService
      # Includes nested items and warranties (both legacy and normalized)
      def create_params
        p = params.key?(:invoice) ? params.require(:invoice) : params
        permitted = p.permit(
          :seller, :seller_name, :purchase_date, :invoice_number, :total_amount, :amount, :category,
          :platform_name, :file, :product_image, :raw_ai_data, :extracted_data,
          :product_name, :brand, :model_number, :description, :warranty_duration, :product_price,
          raw_ai_data: {},
          extracted_data: {},
          warranties: [ :component, :component_name, :duration_months, :warranty_months, :source_text, :description ],
          items: [
            :product_name, :brand, :model_number, :model, :category, :description, :price, :product_price,
            { specifications: {} },
            warranties: [ :component, :component_name, :duration_months, :warranty_months, :source_text, :description ],
            item_warranties: [ :component_name, :duration_months ]
          ],
          # Standard Rails nested attributes for update flow
          invoice_items_attributes: [
            :id,
            :product_name,
            :brand,
            :model,
            :model_number,
            :price,
            :category,
            :description,
            :_destroy,
            { specifications: {} },
            {
              item_warranties_attributes: [
                :id,
                :component_name,
                :component,
                :duration_months,
                :warranty_months,
                :_destroy
              ]
            }
          ]
        )

        if p[:extracted_data].is_a?(ActionController::Parameters)
          permitted[:extracted_data] = p[:extracted_data].to_unsafe_h
        end

        if p[:raw_ai_data].is_a?(ActionController::Parameters)
          permitted[:raw_ai_data] = p[:raw_ai_data].to_unsafe_h
        end

        permitted
      end

      # Permitted params for invoice update
      # Uses Rails nested attributes format for proper update behavior
      def permitted_update_params
        p = params.key?(:invoice) ? params.require(:invoice) : params
        p.permit(
          :seller, :seller_name, :purchase_date, :invoice_number,
          :total_amount, :amount, :category, :platform_name,
          :file, :product_image,
          :product_name, :brand, :model_number, :description,
          :warranty_duration, :product_price,
          # Support for custom items array (current frontend format)
          items: [
            :id, :product_name, :brand, :model_number, :model,
            :category, :description, :price, :product_price,
            :_destroy,
            { specifications: {} },
            {
              warranties: [
                :id, :component_name, :component,
                :duration_months, :warranty_months,
                :_destroy
              ],
              item_warranties: [
                :id, :component_name, :component,
                :duration_months, :warranty_months,
                :_destroy
              ]
            }
          ],
          # Standard Rails nested attributes for proper update behavior
          invoice_items_attributes: [
            :id,
            :product_name,
            :brand,
            :model,
            :model_number,
            :price,
            :category,
            :description,
            :_destroy,
            { specifications: {} },
            {
              item_warranties_attributes: [
                :id,
                :component_name,
                :component,
                :duration_months,
                :warranty_months,
                :_destroy
              ]
            }
          ]
        )
      end

      def invoice_data(invoice, include_warranties: false)
        first_item = invoice.invoice_items.first
        data = {
          id:                 invoice.id,
          product_name:       first_item&.product_name,
          brand:              first_item&.brand,
          model_number:       first_item&.model_number,
          seller:             invoice.seller,
          invoice_number:     invoice.invoice_number,
          amount:             invoice.total_amount&.to_f,
          formatted_amount:   invoice.formatted_amount,
          purchase_date:      invoice.purchase_date,
          warranty_duration:  invoice.warranty_duration,
          warranty_status:    invoice.warranty_status,
          expires_at:         invoice.expires_at,
          days_remaining:     invoice.days_remaining,
          category:           first_item&.category,
          product_image_url:  invoice.product_image_url,
          has_product_image:  invoice.product_image.attached?,
          product_image_file_url: invoice.product_image.attached? ? Rails.application.routes.url_helpers.rails_blob_url(invoice.product_image, host: api_host) : nil,
          description:        first_item&.description,
          original_filename:  invoice.original_filename,
          ocr_status:         invoice.ocr_status,
          ocr_error_message:  invoice.ocr_error_message,
          has_file:           invoice.file.attached?,
          file_url:           invoice.file.attached? ? Rails.application.routes.url_helpers.rails_blob_url(invoice.file, host: api_host) : nil,
          created_at:         invoice.created_at,
          updated_at:         invoice.updated_at
        }

        if include_warranties
          # New Multi-item structure
          data[:items] = invoice.invoice_items.map do |item|
            {
              id: item.id,
              product_name: item.product_name,
              brand: item.brand,
              model_number: item.model_number,
              category: item.category,
              description: item.description,
              specifications: item.specifications,
              warranties: item.warranties.map do |w|
                {
                  id: w.id,
                  component: w.component,
                  duration_months: w.duration_months,
                  expires_at: w.expires_at,
                  days_remaining: w.days_remaining,
                  status: w.status == "expiring" ? "expiring_soon" : w.status
                }
              end
            }
          end

          data[:product_warranties] = []
        end

        data
      end

      def api_host
        ENV.fetch("APP_URL", request.base_url)
      end

      # Estimate completion time based on OCR status
      def estimate_completion_time(invoice)
        case invoice.ocr_status
        when "pending"
          "Processing will start shortly"
        when "processing"
          "Typically completes within 15-30 seconds"
        when "completed"
          "Processing completed"
        when "failed"
          nil
        else
          nil
        end
      end

      # Notification logic moved to CentralizedNotificationService
    end
  end
end
