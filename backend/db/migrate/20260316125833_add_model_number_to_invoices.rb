class AddModelNumberToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :model_number, :string
  end
end
