class CreateGmailConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :gmail_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email
      t.string :access_token
      t.string :encrypted_refresh_token
      t.datetime :token_expires_at
      t.datetime :last_sync_at
      t.integer :sync_status

      t.timestamps
    end
  end
end
