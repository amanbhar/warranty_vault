class AddWarrantyFieldsToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :warranty_duration, :integer
    add_column :invoices, :expires_at, :date
    add_column :invoices, :warranty_status, :integer
  end
end
