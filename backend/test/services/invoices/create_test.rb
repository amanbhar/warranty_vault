# frozen_string_literal: true

require "test_helper"

class Invoices::CreateTest < ActiveSupport::TestCase
  test "creates an invoice with nested items and item warranties" do
    user = create_user

    result = Invoices::Create.call(
      user: user,
      params: {
        invoice_number: "INV-123",
        purchase_date: "2026-01-01",
        seller_name: "Amazon",
        platform_name: "Amazon",
        total_amount: 49999,
        items: [
          {
            product_name: "Washing Machine",
            brand: "Samsung",
            model: "WW80",
            price: 49999,
            category: "appliances",
            item_warranties: [
              { component_name: "product", duration_months: 24 }
            ]
          }
        ]
      }
    )

    assert_predicate result, :success?
    assert_not_nil result.invoice
    assert_equal 1, result.invoice.invoice_items.count
    assert_equal 1, result.invoice.invoice_items.first.item_warranties.count
  end

  test "returns error when validation fails" do
    user = create_user

    result = Invoices::Create.call(
      user: user,
      params: {
        seller_name: nil,
        purchase_date: nil,
        items: []
      }
    )

    refute_predicate result, :success?
    assert_not_nil result.error
    assert_not_nil result.details
  end

  test "creates multiple items with multiple warranties each" do
    user = create_user

    result = Invoices::Create.call(
      user: user,
      params: {
        invoice_number: "INV-456",
        purchase_date: "2026-01-01",
        seller_name: "Best Buy",
        total_amount: 1500,
        items: [
          {
            product_name: "TV",
            brand: "Sony",
            price: 1000,
            item_warranties: [
              { component_name: "product", duration_months: 24 },
              { component_name: "panel", duration_months: 36 }
            ]
          },
          {
            product_name: "Sound Bar",
            brand: "Bose",
            price: 500,
            item_warranties: [
              { component_name: "product", duration_months: 12 }
            ]
          }
        ]
      }
    )

    assert_predicate result, :success?
    assert_equal 2, result.invoice.invoice_items.count

    tv_item = result.invoice.invoice_items.find_by(product_name: "TV")
    assert_equal 2, tv_item.item_warranties.count

    soundbar = result.invoice.invoice_items.find_by(product_name: "Sound Bar")
    assert_equal 1, soundbar.item_warranties.count
  end

  private

  def create_user
    User.create!(
      email: "inv-create-test-#{SecureRandom.hex(4)}@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )
  end
end
