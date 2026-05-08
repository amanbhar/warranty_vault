# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Production: Frontend URL from environment
    # Development: localhost and Vercel preview deployments
    origins(
      ENV.fetch("FRONTEND_URL", "http://localhost:3006"),
      "http://localhost:3006",
      "http://127.0.0.1:3006",
      /https:\/\/.*\.vercel\.app$/  # Vercel preview deployments
    )

    # Allow all API resources with credentials (cookies)
    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true,
      # Expose custom headers to the browser
      expose: [ "Authorization", "X-User-Id" ],
      # Allow cookies to be sent cross-origin
      max_age: 86400 # 24 hours
  end
end
