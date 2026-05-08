# frozen_string_literal: true

class UserReminderPreference < ApplicationRecord
  belongs_to :user

  enum :reminder_type, { default: 0, custom: 1 }, prefix: true

  validates :days_before_expiry, presence: true, uniqueness: { scope: [ :user_id, :reminder_type ] }
  validates :days_before_expiry, numericality: { greater_than_or_equal_to: 0 }

  # Note: Callbacks removed - new NotificationServiceV2 handles reminder creation in controller
end
