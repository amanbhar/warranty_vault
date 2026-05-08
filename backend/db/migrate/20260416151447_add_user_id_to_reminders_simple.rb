class AddUserIdToRemindersSimple < ActiveRecord::Migration[8.0]
  def change
    # Add user_id column (nullable for now)
    add_column :reminders, :user_id, :integer
    add_foreign_key :reminders, :users, column: :user_id

    # Make user_id not null after backfill
    reversible do |dir|
      dir.up do
        # Backfill user_id for existing reminders
        Reminder.reset_column_information
        Reminder.find_each do |reminder|
          reminder.update_column(:user_id, reminder.invoice_item.invoice.user_id)
        end

        change_column_null :reminders, :user_id, false
      end

      dir.down do
        change_column_null :reminders, :user_id, true
      end
    end

    # Add new composite unique index for deduplication
    # Note: We keep the old indexes for now to avoid conflicts
    add_index :reminders, [ :user_id, :invoice_item_id, :reminder_type, :remind_at ], unique: true, name: 'idx_unique_reminders_v2'

    # Add index for performance
    add_index :reminders, [ :user_id, :sent, :remind_at ]
  end
end
