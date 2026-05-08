class CreateUserReminderPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :user_reminder_preferences do |t|
      t.belongs_to :user, null: false, foreign_key: true
      t.integer :days_before_expiry, null: false
      t.integer :reminder_type, default: 0, null: false # 0: default, 1: custom

      t.timestamps
    end
  end
end
