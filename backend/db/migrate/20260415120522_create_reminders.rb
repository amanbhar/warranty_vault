class CreateReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :reminders do |t|
      t.belongs_to :invoice_item, null: false, foreign_key: true
      t.datetime :remind_at, null: false
      t.integer :reminder_type, default: 0 # 0: default, 1: custom
      t.boolean :sent, default: false

      t.timestamps
    end

    add_index :reminders, [ :remind_at, :sent ], name: "idx_reminders_remind_sent"
  end
end
