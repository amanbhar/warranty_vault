module Api
  module V1
    class GmailConnectionsController < ApplicationController
      before_action :set_gmail_connection, only: [ :show, :sync, :disconnect ]

      # GET /api/v1/gmail/connection
      def show
        if @gmail_connection
          render json: {
            connection: {
              id: @gmail_connection.id,
              email: @gmail_connection.email,
              connected: true,
              active: @gmail_connection.active?,
              last_sync_at: @gmail_connection.last_sync_at,
              sync_status: @gmail_connection.sync_status
            }
          }
        else
          render json: {
            connection: {
              connected: false
            }
          }
        end
      end

      # POST /api/v1/gmail/connect
      def connect
        # Uses the root /auth/google route which handles OmniAuth
        render json: {
          oauth_url: "#{request.base_url}/auth/google?purpose=gmail_connect&token=#{CGI.escape(current_user.generate_jwt)}",
          message: "Redirect user to Google OAuth"
        }
      end

      # POST /api/v1/gmail/callback
      def callback
        render json: { message: "Use Google OAuth callback redirect flow" }, status: :method_not_allowed
      end

      # POST /api/v1/gmail/sync
      def sync
        unless @gmail_connection&.active?
          return render json: { error: "Gmail not connected or inactive" }, status: :unprocessable_entity
        end

        # Trigger sync job
        GmailImportJob.perform_later(current_user.id)

        render json: {
          message: "Gmail sync started",
          status: "processing"
        }
      end

      # DELETE /api/v1/gmail/disconnect
      def disconnect
        if @gmail_connection
          @gmail_connection.mark_as_disconnected!
          @gmail_connection.destroy!
        end

        render json: { message: "Gmail disconnected successfully" }
      end

      # GET /api/v1/gmail/suggestions
      def suggestions
        # Placeholder for Gmail import suggestions
        # In production, this would fetch pending items from Gmail sync
        render json: {
          suggestions: [],
          message: "No pending suggestions"
        }
      end

      private

      def set_gmail_connection
        @gmail_connection = current_user.gmail_connection
      end
    end
  end
end
