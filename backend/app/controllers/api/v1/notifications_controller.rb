module Api
  module V1
    class NotificationsController < ApplicationController
      before_action :set_notification, only: [ :show, :mark_as_read, :destroy ]

      # GET /api/v1/notifications
      def index
        options = {
          page: params[:page] || 1,
          per_page: params[:per_page] || 20,
          unread_only: params[:unread] == "true",
          type: params[:type]
        }

        result = NotificationService.get_notifications(current_user, options)

        render json: {
          notifications: result[:notifications].map(&:serialize),
          unread_count: result[:unread_count],
          pagination: result[:pagination]
        }
      end

      # GET /api/v1/notifications/:id
      def show
        render json: { notification: @notification.serialize }
      end

      # POST /api/v1/notifications/:id/mark_read
      def mark_as_read
        result = NotificationService.mark_as_read(@notification.id, current_user)

        if result[:success]
          render json: {
            notification: result[:notification].serialize,
            message: "Notification marked as read"
          }
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/notifications/mark_all_read
      def mark_all_read
        result = NotificationService.mark_all_as_read(current_user)

        render json: {
          success: true,
          count: result[:count],
          message: "All notifications marked as read"
        }
      end

      # PUT /api/v1/notifications/mark_all_as_read
      def mark_all_as_read
        result = NotificationService.mark_all_as_read(current_user)

        render json: {
          success: true,
          count: result[:count],
          message: "All notifications marked as read"
        }
      end

      # DELETE /api/v1/notifications/:id
      def destroy
        result = NotificationService.delete_notification(@notification.id, current_user)

        if result[:success]
          render json: {
            success: true,
            message: "Notification deleted"
          }
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/notifications/unread_count
      def unread_count
        count = NotificationService.unread_count(current_user)

        render json: { unread_count: count }
      end

      private

      def set_notification
        @notification = current_user.notifications.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Notification not found" }, status: :not_found
      end
    end
  end
end
