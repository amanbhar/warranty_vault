class AddOcrStatusToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :ocr_status, :integer
    add_column :invoices, :ocr_error_message, :text
  end
end
