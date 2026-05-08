class SeedDefaultReminderPreferences < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      [ 30, 7, 0 ].each do |days|
        user.user_reminder_preferences.find_or_create_by!(days_before_expiry: days, reminder_type: :default)
      end
    end
  end

  def down
    UserReminderPreference.where(reminder_type: :default).delete_all
  end
end
