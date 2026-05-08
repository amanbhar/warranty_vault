# frozen_string_literal: true

class Reminder < ApplicationRecord
  belongs_to :item_warranty
  has_one :invoice_item, through: :item_warranty
  belongs_to :user

  enum :reminder_type, { default: 0, custom: 1 }, prefix: true

  validates :remind_at, presence: true
  validates :reminder_type, presence: true
  validates :user_id, presence: true
  validates :item_warranty_id, presence: true

  validate :no_reminder_after_expiry
  validate :max_reminders_limit
  
  # validates :reminder_type, uniqueness: {
  #   scope: [:user_id, :item_warranty_id],
  #   message: "has already been set for this warranty/type"
  # }

  scope :pending, -> { where(sent: false) }
  scope :due, -> { pending.where("remind_at <= ?", Time.current) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_warranty, ->(warranty_id) { where(item_warranty_id: warranty_id) }

  private

  def no_reminder_after_expiry
    return unless item_warranty && remind_at
    return if sent? # Allow historical record of past-due notifications

    expiry_date = item_warranty.expires_at
    return unless expiry_date

    if remind_at.to_date > expiry_date.to_date
      errors.add(:remind_at, "cannot be after warranty expiry date")
    end
  end

  def max_reminders_limit
    return unless item_warranty
    # User requested a limit of 5 reminders per warranty
    if item_warranty.reminders.count >= 5 && new_record?
      errors.add(:base, "Maximum 5 reminders allowed per warranty")
    end
  end
end
