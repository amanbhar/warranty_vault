class InvoiceItem < ApplicationRecord
  belongs_to :invoice
  has_many :item_warranties, dependent: :destroy
  has_many :warranties, -> { order(:component_name) }, class_name: "ItemWarranty", dependent: :destroy
  has_many :reminders, through: :item_warranties

  accepts_nested_attributes_for :item_warranties, allow_destroy: true, reject_if: :all_blank

  alias_attribute :model_number, :model

  # Note: after_save callback removed - new NotificationServiceV2 handles reminder updates

  def status
    WarrantyStatusCalculator.product_status(item_warranties)
  end

  def nearest_expiry_date
    item_warranties.where.not(expires_at: nil).minimum(:expires_at)
  end

  validates :product_name, presence: true
  validates :brand, presence: true

  # Specifications is a JSONB field for flexible product-specific data
  # e.g., { "color": "Silver", "size": "236L", "energy_rating": "3 Star" }
end
