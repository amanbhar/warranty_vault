class RemoveUniqueIndexFromReminders < ActiveRecord::Migration[8.0]
  def change
    # Remove unique constraint to allow multiple reminders of the same type
    remove_index :reminders, name: "idx_unique_reminders_warranty", if_exists: true

    # Add regular index for performance (not unique)
    add_index :reminders, [:user_id, :item_warranty_id, :reminder_type], name: "idx_reminders_lookup"
  end
end
