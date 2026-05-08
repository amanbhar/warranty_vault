class AddIndexesToWarrantyNotifications < ActiveRecord::Migration[8.0]
  def change
    # Index for finding warranties due for reminder
    add_index :product_warranties, [ :reminder_sent, :expires_at ], name: 'idx_pw_reminder_expires'

    # Index for finding notifications by user and type
    add_index :notifications, [ :user_id, :notification_type ], name: 'idx_notifications_user_type'

    # Index for unread notifications count
    add_index :notifications, [ :user_id, :read ], name: 'idx_notifications_user_read'

    # Index for recent notifications
    add_index :notifications, [ :created_at ], name: 'idx_notifications_created_at'
  end
end
