# frozen_string_literal: true

class ItemWarranty < ApplicationRecord
  belongs_to :invoice_item, touch: true
  has_many :reminders, dependent: :destroy

  validates :component_name, presence: true
  validates :component_name, uniqueness: { scope: :invoice_item_id }
  validates :duration_months, numericality: { greater_than: 0 }
  validates :start_date, presence: true
  validate :expires_at_must_be_after_start_date

  before_validation :normalize_component_name
  before_validation :calculate_dates

  scope :active, -> { where("expires_at > ?", Date.current) }
  scope :expired, -> { where("expires_at <= ?", Date.current) }
  scope :expiring_soon, -> { where(expires_at: Date.current..30.days.from_now.to_date) }

  alias_attribute :component, :component_name

  def active?
    expires_at.present? && expires_at > Date.current
  end

  def expired?
    expires_at.present? && expires_at <= Date.current
  end

  def status
    WarrantyStatusCalculator.warranty_status(expires_at)
  end

  def expiring_soon?(days = 30)
    expires_at.present? && (Date.current..days.days.from_now.to_date).cover?(expires_at)
  end

  def days_remaining
    return 0 unless expires_at

    [ (expires_at - Date.current).to_i, 0 ].max
  end

  def component_display_name
    component_name.to_s.humanize.titleize
  end

  def duration_display
    return "N/A" unless duration_months.present? && duration_months > 0

    years = duration_months / 12
    months = duration_months % 12

    parts = []
    parts << "#{years} year#{years > 1 ? 's' : ''}" if years > 0
    parts << "#{months} month#{months > 1 ? 's' : ''}" if months > 0

    parts.join(", ")
  end

  def years
    (duration_months / 12).to_i
  end

  def months_only
    (duration_months % 12).to_i
  end

  def calculate_expires_at
    calculate_dates
  end

  private

  def normalize_component_name
    self.component_name = component_name.to_s.downcase.strip
  end

  def calculate_dates
    # Always pull from invoice purchase_date if not explicitly overridden or if we want to sync
    purchase_date = invoice_item&.invoice&.purchase_date
    self.start_date = purchase_date if start_date.blank? || (purchase_date.present? && start_date != purchase_date)

    return unless start_date.present? && duration_months.present?

    self.expires_at = start_date + duration_months.months
  end

  def expires_at_must_be_after_start_date
    return unless start_date && expires_at
    return unless expires_at <= start_date
    
    errors.add(:expires_at, "must be after start date")
  end
end
