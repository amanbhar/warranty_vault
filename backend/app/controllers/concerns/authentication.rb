# frozen_string_literal: true

# Simple Authentication concern for cookie-based JWT authentication
module Authentication
  extend ActiveSupport::Concern

  COOKIE_NAME = "_warranty_vault_auth"

  included do
    before_action :authenticate_user!
  end

  class_methods do
    def skip_authentication(**options)
      skip_before_action :authenticate_user!, **options
    end
  end

  private

  def authenticate_user!
    token = extract_token_from_cookie || extract_token_from_header

    if token.present?
      payload = JwtService.decode(token)
      if payload && payload[:user_id]
        @current_user = User.find_by(id: payload[:user_id])

        # Check if user's email is verified
        if @current_user.present? && !@current_user.can_login?
          render json: {
            error: "Email not verified. Please check your email and verify your account before logging in."
          }, status: :unauthorized
          return
        end

        return if @current_user.present?
      end
    end

    @current_user = nil
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def current_user
    @current_user
  end

  def authenticated?
    @current_user.present?
  end

  def set_auth_cookie(token)
    cookies[COOKIE_NAME] = {
      value: token,
      httponly: true,
      same_site: :lax,
      path: "/",
      expires: 7.days.from_now,
      secure: Rails.env.production?
    }
  end

  def clear_auth_cookie
    cookies.delete(COOKIE_NAME, path: "/")
  end

  def extract_token_from_cookie
    cookies[COOKIE_NAME]
  end

  def extract_token_from_header
    header = request.headers["Authorization"]
    return unless header.present?

    parts = header.split(" ")
    return unless parts.size == 2 && parts.first.downcase == "bearer"

    parts.last
  end
end
