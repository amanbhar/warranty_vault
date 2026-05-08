# Mailer for warranty-related email notifications
#
# Usage:
#   WarrantyMailer.with(user:, invoice:, warranty:, days_remaining:).warranty_expiring_soon.deliver_later
#   WarrantyMailer.with(user:, invoice:, warranty:).warranty_expired.deliver_later
class WarrantyMailer < ApplicationMailer
  default from: ENV.fetch("SMTP_FROM", "noreply@warrantyvault.com")

  # Send warranty expiration reminder email (30 days before expiry)
  def warranty_expiring_soon
    @user           = params[:user]
    @invoice        = params[:invoice]
    @item           = params[:item]
    @warranty       = params[:warranty]
    @days_remaining = params[:days_remaining]
    @product_name   = @item&.product_name || @invoice&.product_name
    @company_name   = ENV.fetch("APP_NAME", "Warranty Vault")
    @support_email  = ENV.fetch("SUPPORT_EMAIL", "support@warrantyvault.com")
    @product_url    = product_url(@invoice)

    mail(
      to: @user.email,
      subject: build_subject,
      template_path: "warranty_mailer",
      template_name: "warranty_expiring_soon"
    )
  end

  # Send warranty expired notification email
  def warranty_expired
    @user           = params[:user]
    @invoice        = params[:invoice]
    @item           = params[:item]
    @warranty       = params[:warranty]
    @days_remaining = 0
    @product_name   = @item&.product_name || @invoice&.product_name
    @company_name   = ENV.fetch("APP_NAME", "Warranty Vault")
    @support_email  = ENV.fetch("SUPPORT_EMAIL", "support@warrantyvault.com")
    @product_url    = product_url(@invoice)

    mail(
      to: @user.email,
      subject: "Warranty expired for #{@product_name}",
      template_path: "warranty_mailer",
      template_name: "warranty_expired"
    )
  end

  private

  def product_url(invoice)
    "#{frontend_base_url}/invoice/#{invoice.id}"
  end

  def build_subject
    if @days_remaining <= 0
      "Warranty expired for #{@product_name}"
    elsif @days_remaining <= 7
      "⚠ Last chance before warranty ends"
    elsif @days_remaining <= 30
      "Warranty ending soon for #{@product_name}"
    else
      "Warranty Reminder: #{@product_name}"
    end
  end
end
