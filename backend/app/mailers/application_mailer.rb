class ApplicationMailer < ActionMailer::Base
  default from: "Warranty Vault <noreply@warrantyvault.com>"
  layout "mailer"

  helper_method :frontend_base_url, :notification_preferences_url

  private

  def frontend_base_url
    ENV.fetch("FRONTEND_URL", "http://localhost:5173")
  end

  def notification_preferences_url
    "#{frontend_base_url}/settings/notifications"
  end
end
