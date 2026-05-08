require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WarrantyVaultApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = true
    config.time_zone = ENV.fetch("APP_TIME_ZONE", "UTC")
    config.active_job.queue_adapter = :sidekiq

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_warranty_vault_session"

    # Load environment variables from .env file
    config.before_configuration do
      env_file = Rails.root.join(".env")
      if File.exist?(env_file)
        require "dotenv"
        Dotenv.load(env_file)
      end
    end

    # AI Service Configuration
    config.ai_services = ActiveSupport::OrderedOptions.new
    config.ai_services.primary = ENV.fetch("PRIMARY_AI_SERVICE", "gemini")
    config.ai_services.fallback = ENV.fetch("FALLBACK_AI_SERVICE", "openai")
    config.ai_services.gemini_model = ENV.fetch("GEMINI_MODEL", "gemini-1.5-flash")
    config.ai_services.openai_model = ENV.fetch("OPENAI_MODEL", "gpt-4o-mini")
    config.ai_services.gemini_temperature = ENV.fetch("GEMINI_TEMPERATURE", "0.1").to_f
    config.ai_services.openai_temperature = ENV.fetch("OPENAI_TEMPERATURE", "0.1").to_f
    config.ai_services.gemini_max_tokens = ENV.fetch("GEMINI_MAX_TOKENS", "2000").to_i
    config.ai_services.openai_max_tokens = ENV.fetch("OPENAI_MAX_TOKENS", "2000").to_i

    # Google Cloud Configuration
    config.google_cloud = ActiveSupport::OrderedOptions.new
    config.google_cloud.project_id = ENV.fetch("GOOGLE_PROJECT_ID", nil)
    config.google_cloud.credentials = ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)

    # Frontend Configuration
    config.frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3006")

    # CORS Configuration
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins ENV.fetch("CORS_ORIGINS", "http://localhost:3006,http://localhost:3000").split(",")
        resource "*",
          headers: :any,
          methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
          credentials: true
      end
    end
  end
end
