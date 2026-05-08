# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  default from: ENV.fetch("SMTP_FROM", "Warranty Vault <noreply@warrantyvault.com>")

  # Send smart reminder email (replaces daily spam)
  def smart_reminder(user)
    @user = user
    @dashboard_url = dashboard_url
    @upload_url = upload_url

    # Get user's warranty statistics
    summary = user.dashboard_summary
    @active_warranties = summary[:active_warranties]
    @count = summary[:total_warranties]

    mail(
      to: user.email,
      subject: "Your warranties are being tracked"
    )
  end

  # Send invoice upload confirmation email
  def invoice_uploaded(user, invoice)
    @user = user
    @invoice = invoice
    @product_name = invoice.product_name || "your product"
    @invoice_url = invoice_url(invoice)
    @product_url = product_url(invoice)

    mail(
      to: user.email,
      subject: "Your invoice is safe with us 👍"
    )
  end

  # Send general notification email
  def notification_email(user, title, message, product_url = nil)
    @user = user
    @title = title
    @message = message
    @product_url = product_url
    @dashboard_url = dashboard_url

    mail(
      to: user.email,
      subject: title
    )
  end

  private

  def product_url(invoice)
    "#{frontend_base_url}/invoice/#{invoice.id}"
  end

  def invoice_url(invoice)
    "#{frontend_base_url}/invoice/#{invoice.id}"
  end

  def dashboard_url
    "#{frontend_base_url}/dashboard"
  end

  def upload_url
    "#{frontend_base_url}/upload"
  end
end
