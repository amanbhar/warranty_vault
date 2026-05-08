class RestoreInvoiceNumberToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :invoice_number, :string unless column_exists?(:invoices, :invoice_number)

    add_index :invoices,
              [ :user_id, :invoice_number ],
              unique: true,
              where: "invoice_number IS NOT NULL",
              name: "index_invoices_on_user_id_and_invoice_number_unique",
              if_not_exists: true
  end
end
