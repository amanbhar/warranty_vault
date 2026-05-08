# frozen_string_literal: true

module Api
  module V1
    class PasswordResetsController < ApplicationController
      skip_authentication only: %i[create update]

      # POST /api/v1/auth/forgot_password
      def create
        email = params[:email].to_s.strip.downcase
        return render json: { error: "Email is required" }, status: :bad_request if email.blank?

        PasswordResetService.request_reset(email)

        render json: {
          success: true,
          message: "If an account exists for this email, a password reset link has been sent."
        }
      rescue => e
        Rails.logger.error "[PasswordResetsController#create] #{e.class}: #{e.message}"
        render json: { error: "Failed to process password reset request" }, status: :internal_server_error
      end

      # POST /api/v1/auth/reset_password
      def update
        token = params[:token].to_s
        password = params[:password].to_s
        password_confirmation = params[:password_confirmation].to_s

        if token.blank? || password.blank? || password_confirmation.blank?
          return render json: { error: "Token, password and password confirmation are required" }, status: :bad_request
        end

        result = PasswordResetService.reset_password(
          token: token,
          password: password,
          password_confirmation: password_confirmation
        )

        if result[:success]
          render json: { success: true, message: "Password reset successful. Please log in." }
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "[PasswordResetsController#update] #{e.class}: #{e.message}"
        render json: { error: "Password reset failed" }, status: :internal_server_error
      end
    end
  end
end
