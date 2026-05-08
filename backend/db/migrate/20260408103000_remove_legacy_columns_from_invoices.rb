# frozen_string_literal: true

class RemoveLegacyColumnsFromInvoices < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :invoices, :products if foreign_key_exists?(:invoices, :products)
    remove_index :invoices, [ :user_id, :invoice_number ], if_exists: true
    remove_index :invoices, name: "index_invoices_on_user_id_and_invoice_number_unique", if_exists: true

    remove_column :invoices, :product_enriched, :boolean
    remove_column :invoices, :enriched_at, :datetime
    remove_column :invoices, :product_image_source, :string
    remove_column :invoices, :product_description, :text
    remove_column :invoices, :official_website, :string
    remove_column :invoices, :product_metadata, :json
    remove_column :invoices, :product_id, :bigint
    remove_column :invoices, :store_address, :string
    remove_column :invoices, :store_phone, :string
    remove_column :invoices, :store_gstin, :string
    remove_column :invoices, :invoice_number, :string
    remove_column :invoices, :invoice_time, :string
    remove_column :invoices, :mrp, :decimal
    remove_column :invoices, :discount, :decimal
    remove_column :invoices, :gst_percentage, :decimal
    remove_column :invoices, :gst_amount, :decimal
    remove_column :invoices, :color, :string
    remove_column :invoices, :specifications, :text
    remove_column :invoices, :part_number, :string
  end
end
