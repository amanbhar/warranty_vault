class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email
      t.string :password_digest
      t.string :first_name
      t.string :last_name
      t.string :google_uid
      t.string :avatar_url
      t.integer :role
      t.datetime :last_sign_in_at
      t.integer :sign_in_count
      t.boolean :email_verified, default: false, null: false
      t.string :verification_token
      t.datetime :verification_sent_at
      t.datetime :email_verified_at
      t.datetime :last_app_reminder_sent_at
      t.datetime :welcome_email_sent_at
      t.boolean :welcome_email_pending
      t.boolean :warranty_alerts_enabled, default: true, null: false
      t.string :password_reset_token
      t.datetime :password_reset_sent_at

      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :google_uid, unique: true
    add_index :users, :verification_token, unique: true
    add_index :users, :email_verified
    add_index :users, :verification_sent_at
    add_index :users, :last_sign_in_at
    add_index :users, :password_reset_sent_at
    add_index :users, :password_reset_token, unique: true
  end
end
