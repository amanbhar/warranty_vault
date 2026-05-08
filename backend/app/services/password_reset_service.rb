# frozen_string_literal: true

class PasswordResetService
  TOKEN_LENGTH = 32
  TOKEN_EXPIRY_MINUTES = 30

  class << self
    def request_reset(email)
      user = User.find_by(email: email)
      return false unless user

      raw_token = SecureRandom.urlsafe_base64(TOKEN_LENGTH)
      hashed_token = hash_token(raw_token)

      user.update_columns(
        password_reset_token: hashed_token,
        password_reset_sent_at: Time.current,
        updated_at: Time.current
      )

      VerificationMailer.password_reset_email(user, raw_token).deliver_now
      true
    rescue => e
      Rails.logger.error "[PasswordResetService.request_reset] #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      false
    end

    def reset_password(token:, password:, password_confirmation:)
      return { success: false, error: "Invalid token" } if token.blank?

      user = User.find_by(password_reset_token: hash_token(token))
      return { success: false, error: "Invalid token" } unless user
      return { success: false, error: "Reset token expired" } if expired?(user)

      unless user.update(password: password, password_confirmation: password_confirmation)
        return { success: false, error: user.errors.full_messages.join(", ") }
      end

      user.update_columns(
        password_reset_token: nil,
        password_reset_sent_at: nil,
        updated_at: Time.current
      )

      { success: true }
    end

    private

    def hash_token(token)
      Digest::SHA256.hexdigest(token)
    end

    def expired?(user)
      return true if user.password_reset_sent_at.blank?

      user.password_reset_sent_at + TOKEN_EXPIRY_MINUTES.minutes < Time.current
    end
  end
end
