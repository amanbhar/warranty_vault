class CreateInvoiceItems < ActiveRecord::Migration[8.0]
  def change
    create_table :invoice_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :product_name
      t.string :brand
      t.string :model_number
      t.string :category
      t.text :description
      t.jsonb :specifications

      t.timestamps
    end
  end
end
