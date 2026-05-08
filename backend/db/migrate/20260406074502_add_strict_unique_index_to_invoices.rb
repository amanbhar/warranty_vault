class AddStrictUniqueIndexToInvoices < ActiveRecord::Migration[8.0]
  def change
    # Remove the existing index if it exists
    remove_index :invoices, name: "index_invoices_on_user_id_and_invoice_number_unique", if_exists: true

    # Add the unique index exactly as requested
    add_index :invoices, [ :user_id, :invoice_number ], unique: true
  end
end
