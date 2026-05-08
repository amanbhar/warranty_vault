# frozen_string_literal: true

module Api
  module V1
    class VerificationController < ApplicationController
      skip_before_action :authenticate_user!, only: [ :verify_email, :verify_email_page, :resend_verification ]

      private

      def frontend_url
        if Rails.env.development?
          "http://localhost:3006"
        elsif Rails.env.production?
          ENV.fetch("FRONTEND_URL", "https://warranty-vault.com")
        else
          "http://localhost:3000"
        end
      end

      public

      # GET /api/v1/verify_email?token=xxxxx (for email links)
      def verify_email_page
        token = params[:token]

        if token.blank?
          return render json: {
            error: "Verification token is required"
          }, status: :bad_request
        end

        result = VerificationService.verify_token(token)

        if result[:success]
          user = result[:user]

          token = user.generate_jwt
          redirect_url = "#{frontend_url}/verify-email-success?token=#{CGI.escape(token)}&verified=true"
          redirect_to redirect_url, allow_other_host: true
        else
          # Redirect to frontend with error
          redirect_url = "#{frontend_url}/verify-email-success?error=#{CGI.escape(result[:error])}"
          redirect_to redirect_url, allow_other_host: true
        end
      rescue => e
        Rails.logger.error "[VerificationController] Error verifying email page: #{e.message}"
        redirect_url = "#{frontend_url}/verify-email-success?error=#{CGI.escape('Verification failed. Please try again.')}"
        redirect_to redirect_url, allow_other_host: true
      end

      # POST /api/v1/verify_email
      def verify_email
        token = params[:token]

        if token.blank?
          return render json: {
            error: "Verification token is required"
          }, status: :bad_request
        end

        result = VerificationService.verify_token(token)

        if result[:success]
          user = result[:user]
          token = user.generate_jwt

          render json: {
            success: true,
            message: "Email verified successfully.",
            token: token,
            user: {
              id: user.id,
              email: user.email,
              first_name: user.first_name,
              last_name: user.last_name,
              email_verified: user.email_verified
            }
          }
        else
          render json: {
            error: result[:error]
          }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "[VerificationController] Error verifying email: #{e.message}"
        render json: {
          error: "Verification failed. Please try again."
        }, status: :internal_server_error
      end

      # POST /api/v1/resend_verification
      def resend_verification
        email = params[:email]

        if email.blank?
          return render json: {
            error: "Email is required"
          }, status: :bad_request
        end

        result = VerificationService.resend_verification(email)

        if result[:success]
          render json: {
            success: true,
            message: result[:message]
          }
        else
          render json: {
            error: result[:error]
          }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "[VerificationController] Error resending verification: #{e.message}"
        render json: {
          error: "Failed to resend verification email. Please try again."
        }, status: :internal_server_error
      end

      # GET /api/v1/verification_status
      def verification_status
        status = VerificationService.verification_status(current_user)

        render json: {
          email_verified: status[:verified],
          needs_verification: status[:needs_verification],
          token_sent_at: status[:token_sent_at],
          expired: status[:expired],
          error: status[:error]
        }
      rescue => e
        Rails.logger.error "[VerificationController] Error getting verification status: #{e.message}"
        render json: {
          error: "Failed to get verification status"
        }, status: :internal_server_error
      end
    end
  end
end
