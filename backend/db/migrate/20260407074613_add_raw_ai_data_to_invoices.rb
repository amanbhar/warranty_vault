class AddRawAiDataToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :raw_ai_data, :jsonb
  end
end
