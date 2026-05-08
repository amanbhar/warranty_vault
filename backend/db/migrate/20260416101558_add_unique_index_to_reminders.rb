# frozen_string_literal: true

class AddUniqueIndexToReminders < ActiveRecord::Migration[7.1]
  def change
    # Add unique index to prevent duplicate reminders
    # This ensures one reminder per user, invoice_item, reminder_type, and remind_at
    add_index :reminders,
              [ :invoice_item_id, :reminder_type, :remind_at ],
              unique: true,
              name: 'index_reminders_unique_per_item_type_time'
  end
end
