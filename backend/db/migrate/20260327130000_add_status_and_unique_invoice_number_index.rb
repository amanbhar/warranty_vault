class AddStatusAndUniqueInvoiceNumberIndex < ActiveRecord::Migration[8.0]
  def up
    # Add processing status column for draft / processed / failed lifecycle
    add_column :invoices, :status, :integer, default: 0, null: false

    # Add index on status for efficient scoping
    add_index :invoices, :status, name: "index_invoices_on_status"

    # Remove the old non-unique invoice_number index so we can replace it
    remove_index :invoices, name: "index_invoices_on_invoice_number", if_exists: true

    # Add a unique composite index: one user cannot have two invoices with the
    # same invoice_number.  NULL values are allowed (invoices without a
    # recognisable invoice_number) and PostgreSQL treats each NULL as distinct,
    # so duplicate NULLs are still permitted.
    add_index :invoices,
              [ :user_id, :invoice_number ],
              unique: true,
              where: "invoice_number IS NOT NULL",
              name: "index_invoices_on_user_id_and_invoice_number_unique"
  end

  def down
    remove_index :invoices, name: "index_invoices_on_user_id_and_invoice_number_unique", if_exists: true
    remove_index :invoices, name: "index_invoices_on_status", if_exists: true
    remove_column :invoices, :status

    # Restore the original simple index
    add_index :invoices, :invoice_number, name: "index_invoices_on_invoice_number"
  end
end
