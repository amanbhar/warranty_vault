# frozen_string_literal: true

# Simple JWT Service for authentication
class JwtService
  class << self
    def encode(payload)
      payload[:exp] = 7.days.from_now.to_i
      JWT.encode(payload, secret_key, "HS256")
    end

    def decode(token)
      begin
        decoded = JWT.decode(token, secret_key, true, algorithm: "HS256")
        HashWithIndifferentAccess.new(decoded.first)
      rescue JWT::ExpiredSignature
        nil
      rescue JWT::InvalidIssuerError, JWT::InvalidIatError, JWT::DecodeError
        nil
      rescue => e
        Rails.logger.error "[JwtService] Decode error: #{e.message}"
        nil
      end
    end

    def secret_key
      Rails.application.secret_key_base || ENV.fetch("JWT_SECRET", "fallback-secret-key-at-least-64-characters-long")
    end
  end
end
