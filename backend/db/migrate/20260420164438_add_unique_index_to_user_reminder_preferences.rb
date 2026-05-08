class AddUniqueIndexToUserReminderPreferences < ActiveRecord::Migration[8.0]
  def change
    # Remove the old index if it exists
    remove_index :user_reminder_preferences, :user_id if index_exists?(:user_reminder_preferences, :user_id)

    # Add composite unique index to prevent duplicate preferences
    add_index :user_reminder_preferences, [ :user_id, :days_before_expiry, :reminder_type ],
              unique: true,
              name: 'index_user_reminder_preferences_on_user_and_days_and_type'
  end
end
