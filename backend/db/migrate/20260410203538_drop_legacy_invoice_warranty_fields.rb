# frozen_string_literal: true

class DropLegacyInvoiceWarrantyFields < ActiveRecord::Migration[8.0]
  def change
    # Remove legacy product-level fields from invoices table
    # These are now stored in invoice_items
    remove_column :invoices, :product_name, :string
    remove_column :invoices, :brand, :string
    remove_column :invoices, :model_number, :string
    remove_column :invoices, :category, :string
    remove_column :invoices, :description, :text
    remove_column :invoices, :expires_at, :date
    remove_column :invoices, :warranty_duration, :integer
    remove_column :invoices, :warranty_status, :integer
    remove_column :invoices, :product_image_url, :string
    remove_column :invoices, :ocr_data, :text

    # Drop the legacy product_warranties table
    # All warranty data has been migrated to item_warranties
    drop_table :product_warranties
  end
end
