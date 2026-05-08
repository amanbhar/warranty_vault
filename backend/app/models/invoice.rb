class Invoice < ApplicationRecord
  belongs_to :user
  has_many :invoice_items, dependent: :destroy
  has_many :warranties, through: :invoice_items, source: :item_warranties

  accepts_nested_attributes_for :invoice_items, allow_destroy: true, reject_if: :all_blank

  delegate :product_name, :brand, :model_number, :category, :description, to: :first_item, allow_nil: true, prefix: false

  def overall_warranty_status
    WarrantyStatusCalculator.invoice_status(invoice_items)
  end

  def first_item
    invoice_items.first
  end

  alias_attribute :seller, :seller_name
  alias_attribute :amount, :total_amount

  has_one_attached :file
  has_one_attached :product_image

  enum :status, { draft: 0, processed: 1, failed: 2 }, default: :processed

  enum :ocr_status, { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :completed, prefix: :ocr
  enum :warranty_status, { expired: 0, active: 1, expiring_soon: 2 }, prefix: true

  validates :seller_name, presence: true, if: :processed?
  validates :purchase_date, presence: true, if: :processed?

  validate :at_least_one_item, if: :processed?

  validates :seller_name, format: { with: /\A.*\S.*\z/m, message: "cannot be blank or whitespace" }, if: :processed?

  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :warranty_duration, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 120 }, allow_nil: true
  validates :invoice_number, uniqueness: { scope: :user_id }, allow_blank: true
  validates :category, length: { maximum: 255 }, allow_blank: true

  validates :purchase_date,
            comparison: {
              less_than_or_equal_to: -> { Date.current + 1.day },
              message: "cannot be in the future"
            },
            if: :purchase_date

  before_save :normalize_invoice_number

  scope :draft,      -> { where(status: :draft) }
  scope :processed,  -> { where(status: :processed) }
  scope :failed_invoices, -> { where(status: :failed) }
  scope :recent,        -> { order(created_at: :desc) }
  scope :by_purchase_date, -> { order(purchase_date: :desc) }
  scope :old_drafts, ->(days = 7) { draft.where("created_at < ?", days.days.ago) }

  scope :search, ->(query) {
    left_joins(:invoice_items)
      .where("invoices.seller_name ILIKE ? OR invoice_items.product_name ILIKE ? OR invoice_items.brand ILIKE ?",
            "%#{query}%", "%#{query}%", "%#{query}%")
      .distinct
  }

  scope :with_expiring_warranties, -> {
    joins(invoice_items: :item_warranties)
      .where("item_warranties.expires_at BETWEEN ? AND ?", Date.current, 30.days.from_now)
      .distinct
  }

  def expiring_within?(days = 30)
    expires_at && (expires_at - Date.current).to_i <= days
  end

  def days_remaining
    return nil unless expires_at
    [ (expires_at - Date.current).to_i, 0 ].max
  end

  def formatted_amount
    total_amount ? "₨. #{total_amount.to_f.round(2)}" : "N/A"
  end

  def mark_ocr_completed
    self.ocr_status = :completed
    save!(validate: true)
  end

  def mark_ocr_failed(error_message = nil)
    self.ocr_status        = :failed
    self.status            = :failed
    self.ocr_error_message = error_message
    save!(validate: false)
  end

  def finalize!
    self.status = :processed
    save(validate: true)
  end

  def destroy_draft!
    raise ActiveRecord::RecordNotDestroyed, "Cannot delete a processed invoice" if processed?
    destroy!
  end

  def product_enriched?
    product_image_url.present? || product_image.attached?
  end

  def processing_complete?
    ocr_completed? && product_enriched?
  end

  def file_path
    return nil unless file.attached?
    file.blob.download
  end

  class << self
    # Compute warranty status integer from expiry date
    # 0 = expired, 1 = active, 2 = expiring_soon
    def warranty_status_from_date(expires_at)
      return 1 if expires_at.nil?
      return 0 if expires_at <= Date.current
      return 2 if expires_at <= 30.days.from_now.to_date
      1
    end
  end

  private

  def at_least_one_item
    if invoice_items.empty? || invoice_items.all?(&:marked_for_destruction?)
      errors.add(:base, "At least one product item is required")
    end
  end

  def normalize_invoice_number
    self.invoice_number = invoice_number.to_s.strip.upcase.presence
  end
end
