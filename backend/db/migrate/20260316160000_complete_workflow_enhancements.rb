class CompleteWorkflowEnhancements < ActiveRecord::Migration[8.0]
  def change
    # Product enrichment fields
    add_column :invoices, :product_enriched, :boolean, default: false unless column_exists?(:invoices, :product_enriched)
    add_column :invoices, :enriched_at, :datetime unless column_exists?(:invoices, :enriched_at)
    add_column :invoices, :product_image_url, :string unless column_exists?(:invoices, :product_image_url)
    add_column :invoices, :product_image_source, :string unless column_exists?(:invoices, :product_image_source)
    add_column :invoices, :product_description, :text unless column_exists?(:invoices, :product_description)
    add_column :invoices, :official_website, :string unless column_exists?(:invoices, :official_website)
    add_column :invoices, :product_metadata, :json unless column_exists?(:invoices, :product_metadata)

    # OCR processing fields
    add_column :invoices, :ocr_status, :integer, default: 0 unless column_exists?(:invoices, :ocr_status)
    add_column :invoices, :ocr_error_message, :text unless column_exists?(:invoices, :ocr_error_message)
    add_column :invoices, :model_number, :string unless column_exists?(:invoices, :model_number)

    # Indexes for performance
    add_index :invoices, :ocr_status unless index_exists?(:invoices, :ocr_status)
    add_index :invoices, :product_enriched unless index_exists?(:invoices, :product_enriched)
    add_index :invoices, :expires_at unless index_exists?(:invoices, :expires_at)
    add_index :invoices, :warranty_status unless index_exists?(:invoices, :warranty_status)
  end
end
