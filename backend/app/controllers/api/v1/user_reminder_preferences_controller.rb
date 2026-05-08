# frozen_string_literal: true

module Api
  module V1
    class UserReminderPreferencesController < ApplicationController
      # GET /api/v1/user_reminder_preferences
      def index
        render json: {
          warranty_alerts_enabled: current_user.warranty_alerts_enabled,
          preferences: current_user.user_reminder_preferences.order(:days_before_expiry)
        }
      end

      # POST /api/v1/user_reminder_preferences
      def create
        @preference = current_user.user_reminder_preferences.new(preference_params)
        @preference.reminder_type = :custom

        if @preference.save
          # Apply custom reminder to all user items via unified service
          NotificationService.apply_custom_reminder(current_user, @preference.days_before_expiry)

          render json: {
            preference: @preference,
            message: "Custom reminder preference added"
          }, status: :created
        else
          render json: {
            error: @preference.errors.full_messages.join(", ")
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/user_reminder_preferences/:id
      def destroy
        @preference = current_user.user_reminder_preferences.find(params[:id])

        if @preference.reminder_type_default?
          return render json: { error: "Default reminders cannot be removed" }, status: :forbidden
        end

        days = @preference.days_before_expiry
        @preference.destroy!

        # Remove matching scheduled reminders without touching defaults
        NotificationService.remove_custom_reminder(current_user, days)

        render json: { message: "Reminder preference removed" }
      end

      # POST /api/v1/user_reminder_preferences/toggle_alerts
      def toggle_alerts
        enabled = params[:enabled]
        current_user.update!(warranty_alerts_enabled: enabled)

        # Note: Reminder processing is handled by the scheduler
        # No need for manual sync with new architecture

        render json: {
          warranty_alerts_enabled: current_user.warranty_alerts_enabled,
          message: "Warranty alerts #{enabled ? 'enabled' : 'disabled'}"
        }
      end

      private

      def preference_params
        params.require(:user_reminder_preference).permit(:days_before_expiry)
      end
    end
  end
end
