# frozen_string_literal: true

module Api
  module V1
    class RemindersController < ApplicationController
      before_action :set_invoice_item
      before_action :set_reminder, only: [ :update, :destroy ]

      # GET /api/v1/invoice_items/:invoice_item_id/reminders
      def index
        render json: {
          reminders: @invoice_item.reminders.order(:remind_at)
        }
      end

      # POST /api/v1/invoice_items/:invoice_item_id/reminders
       def create
         unless params[:warranty_id].present?
           render json: { error: "warranty_id is required" }, status: :unprocessable_entity
           return
         end

         warranty = @invoice_item.item_warranties.find(params[:warranty_id])
         @reminder = warranty.reminders.new(reminder_params)
        @reminder.reminder_type = :custom
        @reminder.user = current_user

        if @reminder.save
          # Reschedule all reminders for this item including the new custom one
          NotificationService.handle_warranty_update(@invoice_item)

          # Send in-app notification
          NotificationService.fire_notification(
            current_user,
            title: "Custom reminder set",
            message: "You'll be reminded about #{@invoice_item.product_name} on #{@reminder.remind_at.strftime('%B %d, %Y')}",
            type: "reminder_created",
            item: @invoice_item,
            meta: { event: "custom_reminder_created", reminder_id: @reminder.id }
          )

          render json: {
            reminder: @reminder,
            message: "Reminder set successfully"
          }, status: :created
        else
          render json: {
            error: @reminder.errors.full_messages.join(", ")
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/invoice_items/:invoice_item_id/reminders/:id
      def update
        if @reminder.default?
          return render json: { error: "Default reminders cannot be edited" }, status: :forbidden
        end

        if @reminder.update(reminder_params)
          render json: {
            reminder: @reminder,
            message: "Reminder updated successfully"
          }
        else
          render json: {
            error: @reminder.errors.full_messages.join(", ")
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/invoice_items/:invoice_item_id/reminders/:id
      def destroy
        if @reminder.default?
          return render json: { error: "Default reminders cannot be deleted" }, status: :forbidden
        end

        @reminder.destroy!

        # Reschedule all reminders for this item after removal
        NotificationService.handle_warranty_update(@invoice_item)

        # Send in-app notification
        NotificationService.fire_notification(
          current_user,
          title: "Reminder removed",
          message: "Your custom reminder for #{@invoice_item.product_name} has been removed.",
          type: "reminder_removed",
          item: @invoice_item,
          meta: { event: "custom_reminder_removed" }
        )

        render json: { message: "Reminder removed" }
      end

      private

      def set_invoice_item
        @invoice_item = current_user.invoice_items.find(params[:invoice_item_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Product not found" }, status: :not_found
      end

      def set_reminder
        @reminder = @invoice_item.reminders.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Reminder not found" }, status: :not_found
      end

      def reminder_params
        params.require(:reminder).permit(:remind_at)
      end
    end
  end
end
