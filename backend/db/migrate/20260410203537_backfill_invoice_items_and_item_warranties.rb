# frozen_string_literal: true

class BackfillInvoiceItemsAndItemWarranties < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    Invoice.reset_column_information
    InvoiceItem.reset_column_information
    ItemWarranty.reset_column_information

    Rails.logger.info "[BackfillInvoiceItemsAndItemWarranties] Starting backfill..."

    backfilled = 0
    skipped = 0

    Invoice.find_each do |invoice|
      # Skip if this invoice already has invoice_items
      if invoice.invoice_items.exists?
        skipped += 1
        next
      end

      # Skip invoices without essential data
      next if invoice[:product_name].blank? && invoice[:brand].blank?

      # Create invoice_item from legacy invoice-level product fields
      item = invoice.invoice_items.create!(
        product_name: invoice[:product_name] || "Unknown Product",
        brand: invoice[:brand] || "Unknown Brand",
        model: invoice[:model_number],
        category: invoice[:category],
        description: invoice[:description],
        price: invoice[:total_amount]
      )

      # Migrate product_warranties to item_warranties
      ProductWarranty.where(invoice_id: invoice.id).find_each do |legacy|
        ItemWarranty.find_or_create_by!(
          invoice_item: item,
          component_name: legacy.component_name
        ) do |w|
          w.duration_months = legacy.warranty_months
          w.start_date = legacy.purchase_date || invoice.purchase_date
          w.expires_at = legacy.expires_at
        end
      end

      # If no product_warranties existed, create a default one from invoice-level warranty fields
      if item.item_warranties.empty? && invoice[:warranty_duration].present?
        item.item_warranties.create!(
          component_name: "product",
          duration_months: invoice[:warranty_duration],
          start_date: invoice.purchase_date
        )
      end

      backfilled += 1
    end

    Rails.logger.info "[BackfillInvoiceItemsAndItemWarranties] Done. Backfilled: #{backfilled}, Skipped: #{skipped}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Backfill cannot be reversed automatically"
  end
end
