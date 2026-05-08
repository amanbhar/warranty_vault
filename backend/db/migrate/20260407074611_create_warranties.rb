class CreateWarranties < ActiveRecord::Migration[8.0]
  def change
    create_table :warranties do |t|
      t.references :invoice_item, null: false, foreign_key: true
      t.string :component
      t.integer :duration_months
      t.date :expires_at

      t.timestamps
    end
  end
end
