module Api
  module V1
    class UsersController < ApplicationController
      # GET /api/v1/users/me
      def me
        render json: {
          user: user_data(current_user),
          stats: {
            total_invoices: current_user.invoices.processed.count,
            active_warranties: current_user.active_warranties_count,
            expiring_soon: current_user.expiring_soon_count,
            expired: current_user.expired_count,
            unread_notifications: current_user.unread_notification_count
          }
        }
      end

      # PUT /api/v1/users/me
      def update
        if current_user.update(user_params)
          render json: {
            user: user_data(current_user),
            message: "Profile updated successfully"
          }
        else
          render json: { error: current_user.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/users/me
      def destroy
        current_user.destroy!
        render json: { message: "Account deleted successfully" }
      end

      private

      def user_params
        params.permit(:first_name, :last_name, :avatar)
      end

      def user_data(user)
        {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
          full_name: user.full_name,
          avatar_url: user.avatar_url,
          role: user.role,
          google_signed_up: user.google_signed_up?,
          created_at: user.created_at
        }
      end
    end
  end
end
