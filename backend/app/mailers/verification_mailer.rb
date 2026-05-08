# frozen_string_literal: true

class VerificationMailer < ApplicationMailer
  default from: ENV.fetch("SMTP_FROM", "Warranty Vault <noreply@warrantyvault.com>")

  # Send email verification
  def verification_email(user, token = nil)
    @user = user
    # Use the provided token or get a fresh one
    @verification_token = token || VerificationService.generate_verification_token(user)
    @verification_url = verification_token_url(@verification_token)

    mail(
      to: user.email,
      subject: "Verify Your Warranty Vault Account"
    )
  end

  # Send password reset
  def password_reset_email(user, token)
    @user = user
    @reset_url = password_reset_url(token)

    mail(
      to: user.email,
      subject: "Reset Your Warranty Vault Password"
    )
  end

  private

  def verification_token_url(token)
    if Rails.env.development?
      "http://localhost:3005/api/v1/verify_email?token=#{token}"
    elsif Rails.env.production?
      "#{ENV.fetch('API_URL', 'https://api.warrantyvault.com')}/api/v1/verify_email?token=#{token}"
    else
      "http://localhost:3005/api/v1/verify_email?token=#{token}"
    end
  end

  def password_reset_url(token)
    frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3006")
    "#{frontend_url}/reset-password?token=#{token}"
  end
end
