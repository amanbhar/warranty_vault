# frozen_string_literal: true

module Api
  module V1
    class AuthenticationController < ApplicationController
      skip_authentication only: %i[signup login google_login google_callback]

      # POST /api/v1/auth/signup
      def signup
        user = User.new(signup_params)

        if user.save
          # Delegate all signup-related notifications and system emails to the unified service
          NotificationService.handle_signup(user)

          render json: {
            message: "Account created successfully! Please check your email to verify your account.",
            user: {
              id: user.id,
              email: user.email,
              first_name: user.first_name,
              email_verified: user.email_verified
            }
          }, status: :created
        else
          render json: { error: user.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/auth/login
      def login
        user = User.find_by(email: params[:email]&.downcase)

        if user&.authenticate(params[:password])
          # Check if email is verified
          unless user.can_login?
            return render json: {
              error: "Please verify your email before logging in. Check your inbox for the verification link."
            }, status: :unauthorized
          end

          token = user.generate_jwt

          # Delegate login notification to unified service
          NotificationService.handle_login(user)

          render json: {
            message: "Login successful",
            token: token,
            user: user_data(user)
          }
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      # POST /api/v1/auth/logout
      def logout
        render json: { message: "Logged out successfully" }
      end

      # GET /auth/google
      def google_login
        redirect_url = "/auth/google_oauth2"
        redirect_url += "?#{request.query_string}" if request.query_string.present?
        redirect_to redirect_url, allow_other_host: true
      end

      # GET /auth/google/callback
      def google_callback
        auth = request.env["omniauth.auth"]
        omniauth_params = request.env["omniauth.params"] || {}
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3006")

        if auth.blank?
          Rails.logger.error "[Google OAuth] Auth data is blank in callback"
          return redirect_to "#{frontend_url}/login?error=authentication_failed", allow_other_host: true
        end

        case omniauth_params["purpose"]
        when "gmail_connect"
          handle_gmail_connection(auth, omniauth_params, frontend_url)
        else
          handle_google_login(auth, frontend_url)
        end
      rescue => e
        Rails.logger.error "[Google OAuth] Critical Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        redirect_to "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3006')}/login?error=authentication_failed", allow_other_host: true
      end

      # GET /api/v1/auth/me
      def me
        render json: { user: user_data(current_user) }
      end

      # GET /auth/failure
      def auth_failure
        error_key = params[:message] || params[:error] || "authentication_failed"
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3006")
        redirect_to "#{frontend_url}/login?error=#{Rack::Utils.escape(error_key)}", allow_other_host: true
      end

      private

      def handle_gmail_connection(auth, omniauth_params, frontend_url)
        current_linked_user = user_from_oauth_token(omniauth_params["token"])
        return redirect_to "#{frontend_url}/gmail-import?error=unauthorized", allow_other_host: true if current_linked_user.blank?

        gmail_connection = current_linked_user.gmail_connection || current_linked_user.build_gmail_connection
        gmail_connection.email = auth.info.email
        gmail_connection.access_token = auth.credentials.token
        gmail_connection.encrypted_refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token.present?
        gmail_connection.token_expires_at = Time.at(auth.credentials.expires_at) if auth.credentials.expires_at.present?
        gmail_connection.sync_status = :active
        gmail_connection.save!

        GmailImportJob.perform_later(current_linked_user.id)
        redirect_to "#{frontend_url}/gmail-import?connected=true", allow_other_host: true
      end

      def handle_google_login(auth, frontend_url)
        user = User.find_or_create_by_google_oauth!(auth)
        token = user.generate_jwt

        # Delegate login notification to unified service
        NotificationService.handle_login(user)

        # Send welcome email for new Google OAuth users (idempotent)
        if !user.welcome_email_sent?
          WelcomeEmailJob.perform_later(user.id, send_on_verify: false)
        end

        # Pass the token directly to the frontend via URL parameter
        redirect_to validated_oauth_callback_url(frontend_url, token), allow_other_host: true
      end

      def signup_params
        params.permit(:email, :password, :password_confirmation, :first_name, :last_name)
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

      def user_from_oauth_token(token)
        payload = JwtService.decode(token)
        return if payload.blank?

        User.find_by(id: payload[:user_id])
      end

      def validated_oauth_callback_url(frontend_url, token)
        # Validate frontend_url is a proper URL and not malicious
        uri = URI.parse(frontend_url)

        # Only allow http and https schemes
        raise ArgumentError, "Invalid URL scheme" unless %w[http https].include?(uri.scheme)

        # Allow common frontend ports to prevent port-based attacks
        allowed_ports = [ 80, 443, 3000, 3001, 3006, 8000, 8080, 8081 ]
        if uri.port && !allowed_ports.include?(uri.port)
          raise ArgumentError, "Invalid port"
        end

        # Prevent open redirect through malformed URLs
        if uri.path.include?("../") || uri.path.include?("%2e%2e")
          raise ArgumentError, "Invalid path"
        end

        # Construct safe callback URL
        "#{uri.scheme}://#{uri.host}#{uri.port ? ":#{uri.port}" : ""}/oauth-callback?token=#{Rack::Utils.escape(token)}"
      rescue URI::InvalidURIError, ArgumentError => e
        Rails.logger.error "[OAuth] Invalid redirect URL: #{e.message}"
        # Fallback to safe default URL
        "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3006')}/oauth-callback?token=#{Rack::Utils.escape(token)}"
      end
    end
  end
end
