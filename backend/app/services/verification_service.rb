# frozen_string_literal: true

# Service for handling email verification logic
class VerificationService
  TOKEN_LENGTH = 32
  TOKEN_EXPIRY_HOURS = 24
  MAX_RESEND_ATTEMPTS = 3
  RESEND_COOLDOWN_MINUTES = 5

  class << self
    # Generate verification token
    def generate_token
      SecureRandom.urlsafe_base64(TOKEN_LENGTH)
    end

    # Generate and assign verification token to user
    def generate_verification_token(user)
      token = generate_token
      hashed_token = hash_token(token)

      user.update_columns(
        verification_token: hashed_token,
        verification_sent_at: Time.current
      )

      Rails.logger.info "[VerificationService] Generated verification token for user #{user.id}"
      token # Return unhashed token for email
    end

    # Generate verification token without saving (for email service)
    def generate_verification_token_only
      generate_token
    end

    # Verify email token
    def verify_token(token)
      return { success: false, error: "Invalid token" } if token.blank?

      hashed_token = hash_token(token)
      user = User.find_by(verification_token: hashed_token)
      return { success: false, error: "Invalid token" } unless user

      if token_expired?(user)
        return { success: false, error: "Token expired" }
      end

      if user.email_verified?
        return { success: false, error: "Email already verified" }
      end

      # Mark email as verified
      user.update_columns(
        email_verified: true,
        email_verified_at: Time.current,
        verification_token: nil,
        verification_sent_at: nil
      )

      Rails.logger.info "[VerificationService] Email verified for user #{user.id}"

      # Don't send welcome email here - send it after first login instead
      { success: true, user: user }
    end

    # Check if token is expired
    def token_expired?(user)
      return true if user.verification_sent_at.blank?

      expiry_time = user.verification_sent_at + TOKEN_EXPIRY_HOURS.hours
      Time.current > expiry_time
    end

    # Resend verification email
    def resend_verification(email)
      user = User.find_by(email: email.downcase)
      return { success: false, error: "User not found" } unless user

      if user.email_verified?
        return { success: false, error: "Email already verified" }
      end

      # Check resend cooldown
      if resend_cooldown_active?(user)
        wait_time = RESEND_COOLDOWN_MINUTES - minutes_since_last_email(user)
        return {
          success: false,
          error: "Please wait #{wait_time.ceil} minutes before requesting another verification email"
        }
      end

      # Generate new token and send email
      generate_verification_token(user)

      if EmailService.send_verification_email(user)
        { success: true, message: "Verification email sent" }
      else
        { success: false, error: "Failed to send verification email" }
      end
    end

    # Check if user can login
    def can_login?(user)
      return false unless user
      return false unless user.email_verified?

      true
    end

    # Get verification status
    def verification_status(user)
      return { verified: false, needs_verification: true } unless user

      if user.email_verified?
        { verified: true, verified_at: user.email_verified_at }
      else
        status = {
          verified: false,
          needs_verification: true,
          token_sent_at: user.verification_sent_at,
          expired: user.verification_sent_at ? token_expired?(user) : nil
        }

        if status[:expired]
          status[:error] = "Verification token expired"
        end

        status
      end
    end

    # Clean up expired tokens (run periodically)
    def cleanup_expired_tokens
      expired_users = User.where(
        "verification_sent_at < ? AND email_verified = ?",
        TOKEN_EXPIRY_HOURS.hours.ago,
        false
      )

      count = expired_users.count
      expired_users.update_all(verification_token: nil, verification_sent_at: nil)

      Rails.logger.info "[VerificationService] Cleaned up #{count} expired verification tokens"
      count
    end

    private

    # Check if resend cooldown is active
    def resend_cooldown_active?(user)
      return false unless user.verification_sent_at
      minutes_since_last_email(user) < RESEND_COOLDOWN_MINUTES
    end

    # Calculate minutes since last email was sent
    def minutes_since_last_email(user)
      return 0 unless user.verification_sent_at
      ((Time.current - user.verification_sent_at) / 60).round
    end

    # Hash token for secure storage
    def hash_token(token)
      Digest::SHA256.hexdigest(token)
    end
  end
end
