# frozen_string_literal: true

module Api
  module V1
    class ProductImagesController < ApplicationController
      before_action :set_invoice
      before_action :authenticate_user!

      # GET /api/v1/invoices/:invoice_id/product_image
      def show
        if @invoice.product_image_url.present?
          render json: {
            success: true,
            product_image_url: @invoice.product_image_url,
            product_image_source: product_image_source_for(@invoice),
            product_enriched: true,
            enriched_at: @invoice.updated_at
          }
        else
          render json: {
            success: false,
            error: "No product image available",
            message: "Product image not found for this invoice"
          }, status: :not_found
        end
      end

      # POST /api/v1/invoices/:invoice_id/product_image/refresh
      def refresh
        unless @invoice.ocr_completed?
          render json: {
            success: false,
            error: "Invoice not processed yet",
            message: "Please wait for invoice processing to complete"
          }, status: :unprocessable_entity
          return
        end

        # Clear existing image
        @invoice.update_columns(
          product_image_url: nil
        )

        # Trigger image fetch
        ProductEnrichmentJob.perform_later(@invoice.id)

        render json: {
          success: true,
          message: "Product image refresh initiated",
          invoice_id: @invoice.id
        }
      end

      # GET /api/v1/invoices/:invoice_id/product_image/status
      def status
        has_image = @invoice.product_image_url.present?
        render json: {
          success: true,
          has_image: has_image,
          product_enriched: has_image,
          enriched_at: has_image ? @invoice.updated_at : nil,
          product_image_source: has_image ? product_image_source_for(@invoice) : nil,
          ocr_completed: @invoice.ocr_completed?
        }
      end

      private

      def set_invoice
        @invoice = current_user.invoices.find(params[:invoice_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      end

      def product_image_source_for(invoice)
        return "user_upload" if invoice.product_image.attached?
        return nil if invoice.product_image_url.blank?

        invoice.product_image_url.include?("/assets/images/") ? "local_default_mapping" : "external"
      end
    end
  end
end
