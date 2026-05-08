class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :product_name
      t.string :brand
      t.string :seller
      t.decimal :amount
      t.date :purchase_date
      t.integer :warranty_duration
      t.integer :warranty_status
      t.text :ocr_data
      t.string :file_url
      t.string :original_filename
      t.string :category
      t.date :expires_at

      t.timestamps
    end
  end
end
