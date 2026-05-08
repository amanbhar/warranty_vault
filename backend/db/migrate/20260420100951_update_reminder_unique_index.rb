class UpdateReminderUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :reminders, name: "idx_unique_reminders_v2" if index_exists?(:reminders, [ :user_id, :invoice_item_id, :reminder_type, :remind_at ], name: "idx_unique_reminders_v2")

    add_index :reminders, [ :user_id, :invoice_item_id, :component, :remind_at ], unique: true, name: "idx_unique_reminders_v3"
  end
end
