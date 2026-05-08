class Notification < ApplicationRecord
  belongs_to :user

  enum :notification_type, {
    info: 0,
    warning: 1,
    success: 2,
    error: 3,
    warranty_expiring: 4,
    warranty_expired: 5,
    invoice_processed: 6,
    ocr_complete: 7,
    system_update: 8,
    invoice_updated: 9,
    invoice_created: 10,
    product_updated: 11,
    daily_engagement: 12
  }

  validates :title, presence: true
  validates :message, presence: true

  # Set default values
  after_initialize :set_defaults, if: :new_record?

  scope :unread, -> { where(read: false) }
  scope :read, -> { where(read: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(notification_type: type) }

  private

  def set_defaults
    self.read ||= false
  end

  public

  # Mark notification as read
  def mark_as_read!
    update(read: true)
  end

  # Mark all notifications for a user as read
  def self.mark_all_as_read(user)
    where(user: user, read: false).update_all(read: true)
  end

  # Serialize for API response
  def serialize
    {
      id: id,
      title: title,
      message: message,
      notification_type: notification_type,
      read: read,
      action_url: action_url,
      metadata: metadata,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601
    }
  end

  # Create warranty expiration notification
  def self.warranty_expiring_notification(user, invoice, days_remaining)
    create!(
      user: user,
      title: "Warranty Expiring Soon",
      message: "Your warranty for #{invoice.product_name} expires in #{days_remaining} days.",
      notification_type: :warranty_expiring,
      action_url: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{invoice.id}"
    )
  end

  # Create warranty expired notification
  def self.warranty_expired_notification(user, invoice)
    create!(
      user: user,
      title: "Warranty Expired",
      message: "Your warranty for #{invoice.product_name} has expired.",
      notification_type: :warranty_expired,
      action_url: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{invoice.id}"
    )
  end

  # Create upload successful notification
  def self.upload_successful_notification(user, invoice)
    create!(
      user: user,
      title: "Invoice Saved",
      message: "Your invoice is saved and we are tracking your product warranty.",
      notification_type: :success,
      action_url: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{invoice.id}"
    )
  end

  def self.ocr_complete_notification(user, invoice)
    create!(
      user: user,
      title: "OCR Review Ready",
      message: "We extracted details for #{invoice.product_name || 'your invoice'}. Review and confirm the warranty data.",
      notification_type: :ocr_complete,
      action_url: "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}/invoice/#{invoice.id}"
    )
  end

  def self.ocr_failed_notification(user, invoice, error_message = nil)
    is_destroyed = !invoice || invoice.destroyed?
    frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
    url = is_destroyed ? "#{frontend_url}/workflow" : "#{frontend_url}/invoice/#{invoice.id}/edit"
    msg = is_destroyed ? "Upload cancelled. We couldn't extract data due to an AI service error. Please try uploading again." : "We couldn't extract data from your invoice. Please enter the details manually. #{error_message}"

    create!(
      user: user,
      title: "OCR Processing Failed",
      message: msg,
      notification_type: :error,
      action_url: url
    )
  end
end
