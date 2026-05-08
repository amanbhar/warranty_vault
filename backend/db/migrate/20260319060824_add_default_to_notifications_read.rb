class AddDefaultToNotificationsRead < ActiveRecord::Migration[8.0]
  def change
    change_column_default :notifications, :read, from: nil, to: false

    # Update existing null values to false
    Notification.where(read: nil).update_all(read: false)
  end
end
