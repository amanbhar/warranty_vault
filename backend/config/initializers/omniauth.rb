# OmniAuth Google OAuth2 Configuration
# Uses ENV variables for credentials - never hardcode

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV.fetch("GOOGLE_CLIENT_ID"),
           ENV.fetch("GOOGLE_CLIENT_SECRET"),
           {
             # Request email, profile, and Gmail access
             scope: "email,profile,https://www.googleapis.com/auth/gmail.readonly",
             redirect_uri: ENV.fetch("GOOGLE_REDIRECT_URI", nil),
             callback_path: "/auth/google/callback",
             access_type: "offline",  # Get refresh token
             prompt: "consent select_account",  # Force consent screen
             include_granted_scopes: true,
             # SSL settings for development
             ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE,
             # Important for API-only Rails apps - disables CSRF state check
             provider_ignores_state: true
           }
end

# Security: Only allow GET and POST for OAuth callbacks
OmniAuth.config.allowed_request_methods = [ :get, :post ]

# Important for Docker/Vite: Set the full host to the BACKEND URL
# This ensures that the redirect_uri sent to Google matches the backend
backend_url = ENV.fetch("APP_URL", "http://localhost:3005")
OmniAuth.config.full_host = backend_url

# Suppress warnings about GET requests (we explicitly allow them above)
OmniAuth.config.silence_get_warning = true

# For API-only apps, we need to handle failures differently
# The on_failure handler catches errors and redirects to frontend
OmniAuth.config.on_failure = proc do |env|
  message_key = env["omniauth.error.type"]
  error_message = env["omniauth.error"].to_s
  strategy_name = env["omniauth.error.strategy"]&.name || "unknown"

  Rails.logger.warn "[OmniAuth] Failure in #{strategy_name}: #{message_key} - #{error_message}"
  Rails.logger.warn "[OmniAuth] Full env dump: #{env.select { |k, v| k.to_s.include?('omniauth') }.inspect}"

  frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3006")
  [ 302, { "Location" => "#{frontend_url}/login?error=#{message_key}" }, [] ]
end
