# frozen_string_literal: true

require "test_helper"

class InvoiceItemTest < ActiveSupport::TestCase
  test "status is active when one warranty is active and another is expired" do
    user = build_user("invoice-item-active")
    invoice = build_invoice(user)
    item = build_item(invoice)

    active = ItemWarranty.create!(invoice_item: item, component_name: "product", duration_months: 24)
    expired = ItemWarranty.create!(invoice_item: item, component_name: "compressor", duration_months: 12)

    active.update_column(:expires_at, 90.days.from_now.to_date)
    expired.update_column(:expires_at, 10.days.ago.to_date)

    assert_equal "active", item.status
  end

  test "status is expiring when no active warranty and one is expiring" do
    user = build_user("invoice-item-expiring")
    invoice = build_invoice(user)
    item = build_item(invoice)

    expiring = ItemWarranty.create!(invoice_item: item, component_name: "product", duration_months: 12)
    expired = ItemWarranty.create!(invoice_item: item, component_name: "compressor", duration_months: 6)

    expiring.update_column(:expires_at, 10.days.from_now.to_date)
    expired.update_column(:expires_at, 20.days.ago.to_date)

    assert_equal "expiring", item.status
  end

  test "status defaults to expired when item has no warranties" do
    user = build_user("invoice-item-empty")
    invoice = build_invoice(user)
    item = build_item(invoice)

    assert_equal "expired", item.status
  end

  private

  def build_user(tag)
    User.create!(
      email: "#{tag}-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
  end

  def build_invoice(user)
    Invoice.create!(
      user: user,
      seller_name: "Store",
      purchase_date: Date.current,
      status: :draft,
      ocr_status: :completed
    )
  end

  def build_item(invoice)
    InvoiceItem.create!(
      invoice: invoice,
      product_name: "AC Unit",
      brand: "CoolBrand"
    )
  end
end
