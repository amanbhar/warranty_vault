# Test helpers for warranty reminder system
module WarrantyTestHelpers
  # Create a warranty with specific expiry date
  def create_warranty(invoice:, component_name: "product", warranty_months: 12, expires_at: nil, reminder_sent: false)
    ProductWarranty.create!(
      invoice: invoice,
      component_name: component_name,
      warranty_months: warranty_months,
      expires_at: expires_at,
      purchase_date: invoice.purchase_date,
      reminder_sent: reminder_sent
    )
  end

  # Create an invoice with warranty for a user
  def create_invoice_with_warranty(user:, purchase_date: Date.current, warranty_months: 12, expires_at: nil)
    invoice = Invoice.create!(
      user: user,
      product_name: "Test Product",
      brand: "Test Brand",
      purchase_date: purchase_date,
      warranty_duration: warranty_months,
      ocr_status: :completed
    )

    expires_at ||= purchase_date + warranty_months.months

    warranty = create_warranty(
      invoice: invoice,
      component_name: "product",
      warranty_months: warranty_months,
      expires_at: expires_at
    )

    { invoice: invoice, warranty: warranty }
  end
end
