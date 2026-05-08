class AddEnhancedFieldsToInvoices < ActiveRecord::Migration[8.0]
  def change
    # Store information fields
    add_column :invoices, :store_address, :string
    add_column :invoices, :store_phone, :string
    add_column :invoices, :store_gstin, :string
    add_column :invoices, :invoice_number, :string
    add_column :invoices, :invoice_time, :string

    # Pricing fields
    add_column :invoices, :mrp, :decimal, precision: 10, scale: 2
    add_column :invoices, :discount, :decimal, precision: 10, scale: 2
    add_column :invoices, :gst_percentage, :decimal, precision: 5, scale: 2
    add_column :invoices, :gst_amount, :decimal, precision: 10, scale: 2

    # Product specification fields
    add_column :invoices, :color, :string
    add_column :invoices, :specifications, :text
    add_column :invoices, :part_number, :string
    add_column :invoices, :serial_number, :string

    # AI confidence and metadata
    add_column :invoices, :confidence_score, :decimal, precision: 3, scale: 2
    add_column :invoices, :metadata, :json

    # Add indexes for better performance
    add_index :invoices, :invoice_number
    add_index :invoices, :serial_number
    add_index :invoices, :confidence_score
  end
end
