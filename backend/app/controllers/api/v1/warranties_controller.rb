# frozen_string_literal: true

module Api
  module V1
    # Controller for managing product warranties
    class WarrantiesController < ApplicationController
      before_action :authenticate_user!

      # GET /api/v1/warranties
      # List all warranties for the current user
      def index
        warranties = ItemWarranty.joins(invoice_item: :invoice)
                                 .where(invoices: { user_id: current_user.id })
                                 .includes(invoice_item: :invoice)
                                 .order(expires_at: :asc)

        warranties = apply_filters(warranties)
        warranties, pagination = paginate(warranties)

        render json: {
          data: serialize_warranties(warranties),
          meta: pagination
        }, status: :ok
      end

      # GET /api/v1/warranties/expiring
      # Get warranties expiring within specified days
      def expiring
        days = params[:days]&.to_i || 30
        warranties = ItemWarranty.joins(invoice_item: :invoice)
                                 .where(invoices: { user_id: current_user.id })
                                 .where("item_warranties.expires_at BETWEEN ? AND ?", Date.current, days.days.from_now)
                                 .includes(invoice_item: :invoice)
                                 .order(expires_at: :asc)

        render json: {
          data: serialize_warranties(warranties),
          meta: { count: warranties.count, days: days }
        }, status: :ok
      end

      # POST /api/v1/warranties/:id/remind
      # Manually trigger a reminder for a specific warranty
      def remind
        warranty = find_warranty(params[:id])

        # Trigger immediate reminder processing by updating warranty context
        NotificationService.handle_warranty_update(warranty.invoice_item)

        # Send in-app notification confirming rescheduling
        NotificationService.fire_notification(
          current_user,
          title: "Reminders rescheduled",
          message: "Reminders rescheduled for #{warranty.invoice_item.product_name}",
          type: "reminder_rescheduled",
          item: warranty.invoice_item,
          meta: { event: "warranty_reminders_rescheduled", warranty_id: warranty.id }
        )

        render json: {
          success: true,
          message: "Reminder scheduled successfully",
          data: serialize_warranty(warranty)
        }, status: :ok
      rescue => e
        Rails.logger.error "[WarrantiesController] Failed to schedule reminder: #{e.message}"
        render json: {
          success: false,
          message: "Failed to schedule reminder: #{e.message}"
        }, status: :unprocessable_entity
      end

      # POST /api/v1/warranties/bulk_remind
      # Trigger reminders for multiple warranties
      def bulk_remind
        warranty_ids = params[:warranty_ids]
        return render json: { error: "warranty_ids required" }, status: :bad_request unless warranty_ids.present?

        warranties = ItemWarranty.joins(invoice_item: :invoice)
                                 .where(invoices: { user_id: current_user.id }, id: warranty_ids)

        success_count = 0
        failed_count = 0
        errors = []

        warranties.find_each do |warranty|
          begin
            # Trigger the reminder flow via unified service
            NotificationService.handle_warranty_update(warranty.invoice_item)
            success_count += 1
          rescue => e
            Rails.logger.error "[WarrantiesController] Bulk remind failed for warranty #{warranty.id}: #{e.message}"
            failed_count += 1
            errors << { warranty_id: warranty.id, error: e.message }
          end
        end

        render json: {
          success: failed_count.zero?,
          message: "Processed #{warranties.count} warranties",
          data: {
            success_count: success_count,
            failed_count: failed_count,
            errors: errors
          }
        }, status: failed_count.zero? ? :ok : :multi_status
      end

      # GET /api/v1/warranties/stats
      # Get warranty statistics for dashboard
      def stats
        base_query = ItemWarranty.joins(invoice_item: :invoice).where(invoices: { user_id: current_user.id })

        stats = {
          total: base_query.count,
          active: base_query.where("item_warranties.expires_at > ?", Date.current).count,
          expiring_soon: base_query.where("item_warranties.expires_at BETWEEN ? AND ?", Date.current, 30.days.from_now).count,
          expired: base_query.where("item_warranties.expires_at < ?", Date.current).count,
          by_component: base_query.group(:component_name).count
        }

        render json: {
          data: stats
        }, status: :ok
      end

      private

      def find_warranty(id)
        ItemWarranty.joins(invoice_item: :invoice)
                       .find_by(invoices: { user_id: current_user.id }, id: id)
                       .tap { |w| raise ActiveRecord::RecordNotFound unless w }
      end

      def apply_filters(query)
        query = query.where(component_name: params[:component]) if params[:component].present?
        query = query.where("item_warranties.expires_at > ?", Date.current) if params[:status] == "active"
        query = query.where("item_warranties.expires_at <= ?", Date.current) if params[:status] == "expired"
        query
      end

      def serialize_warranties(warranties)
        warranties.map { |w| serialize_warranty(w) }
      end

      def serialize_warranty(warranty)
        invoice = warranty.invoice_item.invoice
        {
          id: warranty.id,
          invoice_id: invoice.id,
          component_name: warranty.component_display_name,
          duration_months: warranty.duration_months,
          expires_at: warranty.expires_at,
          purchase_date: invoice.purchase_date,
          days_remaining: warranty.days_remaining,
          status: warranty.status,
          invoice: {
            id: invoice.id,
            product_name: warranty.invoice_item.product_name,
            brand: warranty.invoice_item.brand,
            purchase_date: invoice.purchase_date
          }
        }
      end
    end
  end
end
