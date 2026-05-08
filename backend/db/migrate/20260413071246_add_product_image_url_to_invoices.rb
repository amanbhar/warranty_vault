class AddProductImageUrlToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :product_image_url, :string
  end
end
