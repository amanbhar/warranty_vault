Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Mount ActionCable server
  mount ActionCable.server => "/cable"

  # Google OAuth routes (must be at root level for OmniAuth middleware)
  # /auth/google -> google_login action -> redirects to /auth/google_oauth2 (OmniAuth)
  # /auth/google_oauth2 -> OmniAuth middleware (automatic, no route needed)
  # /auth/google/callback -> google_callback action
  get "auth/google", to: "api/v1/authentication#google_login", as: :auth_google
  get "auth/google/callback", to: "api/v1/authentication#google_callback", as: :auth_google_callback
  post "auth/google/callback", to: "api/v1/authentication#google_callback"
  get "auth/failure", to: "api/v1/authentication#auth_failure", as: :auth_failure

  # API Routes
  namespace :api do
    namespace :v1 do
      # Authentication
      post "auth/signup", to: "authentication#signup"
      post "auth/login", to: "authentication#login"
      post "auth/logout", to: "authentication#logout"
      get "auth/me", to: "authentication#me"
      # Note: /auth/google and /auth/google/callback are at root level for OmniAuth

      # Email Verification
      # Email verification routes
      post "verify_email", to: "verification#verify_email"
      get "verify_email", to: "verification#verify_email_page"  # For email links
      post "resend_verification", to: "verification#resend_verification"
      get "verification_status", to: "verification#verification_status"
      post "auth/forgot_password", to: "password_resets#create"
      post "auth/reset_password", to: "password_resets#update"

      # User
      get "users/me", to: "users#me"
      put "users/me", to: "users#update"
      delete "users/me", to: "users#destroy"

      # Invoice Scan (AI scanning without creating record)
      resources :invoice_scans, only: [] do
        collection do
          post :scan
        end
      end

      # Invoices
      resources :invoices do
        member do
          get  :download
          get  :preview
          get  :ocr_status
          post :retry_ocr
          post :finalize   # User confirms OCR result → marks invoice as processed
          delete :cancel   # User cancels upload flow → destroys draft invoice
        end
        collection do
          get :stats
          get :dashboard
          get :export
          post :scan_upload
        end

        # Product image nested routes
        resources :product_images, only: [ :show, :create ], controller: "product_images" do
          member do
            post :refresh
            get :status
          end
        end

        resources :invoice_items, only: [] do
          resources :reminders, only: [ :index, :create, :update, :destroy ]
        end
      end

      # Removed deprecated invoices_workflow endpoints

      # Product enrichment (image + description from free APIs)
      resources :products, only: [ :index, :show ] do
        collection do
          get :enrich
          get :search
          get :stats
          post :refresh
        end
        member do
          get :support_info
        end
      end

      # Support info by brand (shortcut)
      get "products/support/:brand", to: "products#support_info", as: :product_support

      # Warranties
      resources :warranties, only: [ :index, :show ] do
        collection do
          get :expiring
          get :stats
          post :bulk_remind
        end
        member do
          post :remind
        end
      end

      # Notifications
      resources :notifications, only: [ :index, :show, :destroy ] do
        member do
          put :mark_as_read
          post :dismiss
        end
        collection do
          put :mark_all_as_read
          get :unread_count
          delete :clear_all
        end
      end

      # Gmail Integration
      get "gmail/connection", to: "gmail_connections#show"
      post "gmail/connect", to: "gmail_connections#connect"
      post "gmail/callback", to: "gmail_connections#callback"
      post "gmail/sync", to: "gmail_connections#sync"
      delete "gmail/disconnect", to: "gmail_connections#disconnect"
      get "gmail/suggestions", to: "gmail_connections#suggestions"

      # User Reminder Preferences
      resources :user_reminder_preferences, only: [ :index, :create, :destroy ] do
        collection do
          post :toggle_alerts
        end
      end
    end
  end

  # Catch-all for API versioning (exclude auth routes)
  namespace :api do
    namespace :v1 do
      get "*path", to: "application#not_found", constraints: ->(request) {
        !request.path.start_with?("/auth/") && !request.path.start_with?("/api/v1/auth/")
      }
    end
  end
end
