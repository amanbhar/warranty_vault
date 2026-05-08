class CreateProductWarranties < ActiveRecord::Migration[8.0]
  def change
    create_table :product_warranties do |t|
      t.references :invoice, null: false, foreign_key: { on_delete: :cascade }
      t.string :component_name, null: false
      t.integer :warranty_months, null: false
      t.date :expires_at
      t.date :purchase_date # Store original purchase date for reference
      t.string :warranty_text # Original text from OCR
      t.boolean :reminder_sent, default: false
      t.datetime :last_reminder_sent_at

      t.timestamps
    end

    # Indexes for efficient queries
    add_index :product_warranties, :expires_at
    add_index :product_warranties, :component_name
    add_index :product_warranties, [ :invoice_id, :component_name ], unique: true
    add_index :product_warranties, [ :expires_at, :reminder_sent ] # For scheduled jobs
  end
end
