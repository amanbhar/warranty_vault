class NormalizeInvoiceSchema < ActiveRecord::Migration[8.0]
  def change
    rename_table :warranties, :item_warranties
    rename_column :invoices, :seller, :seller_name
    rename_column :invoices, :amount, :total_amount
    rename_column :invoice_items, :model_number, :model
    rename_column :item_warranties, :component, :component_name

    # Rename indexes created by the original warranties table
    if index_name_exists?(:item_warranties, "index_warranties_on_invoice_item_id")
      rename_index :item_warranties, "index_warranties_on_invoice_item_id", "index_item_warranties_on_invoice_item_id"
    end

    add_column :invoices, :platform_name, :string
    add_column :invoice_items, :price, :decimal, precision: 12, scale: 2
    add_column :item_warranties, :start_date, :date

    # Remove duplicate warranties (keep the one with lowest id per group)
    execute <<-SQL
      DELETE FROM item_warranties
      WHERE id NOT IN (
        SELECT MIN(id) FROM item_warranties
        GROUP BY invoice_item_id, component_name
      )
    SQL

    add_index :item_warranties, :expires_at
    add_index :item_warranties, %i[invoice_item_id component_name], unique: true
  end
end
