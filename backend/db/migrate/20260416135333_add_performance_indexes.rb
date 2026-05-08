class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Indexes for faster queries on commonly filtered columns

    # Users table
    add_index :users, :email_verified unless index_exists?(:users, :email_verified)
    add_index :users, :last_sign_in_at unless index_exists?(:users, :last_sign_in_at)

    # Invoices table
    add_index :invoices, [ :user_id, :status ] unless index_exists?(:invoices, [ :user_id, :status ])
    add_index :invoices, [ :user_id, :created_at ], order: { created_at: :desc } unless index_exists?(:invoices, [ :user_id, :created_at ])
    add_index :invoices, :ocr_status unless index_exists?(:invoices, :ocr_status)

    # Invoice items table
    add_index :invoice_items, :invoice_id unless index_exists?(:invoice_items, :invoice_id)

    # Item warranties table
    add_index :item_warranties, :expires_at unless index_exists?(:item_warranties, :expires_at)

    # Notifications table
    add_index :notifications, [ :user_id, :created_at ], order: { created_at: :desc } unless index_exists?(:notifications, [ :user_id, :created_at ])
    add_index :notifications, [ :user_id, :notification_type ] unless index_exists?(:notifications, [ :user_id, :notification_type ])

    # Composite index for dashboard queries
    add_index :item_warranties, [ :invoice_item_id, :expires_at ] unless index_exists?(:item_warranties, [ :invoice_item_id, :expires_at ])
  end
end
