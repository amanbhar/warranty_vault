# frozen_string_literal: true

require "test_helper"

class Invoices::UpdateTest < ActiveSupport::TestCase
  test "replaces invoice items and item warranties transactionally" do
    invoice = create_invoice_with_item

    result = Invoices::Update.call(
      invoice: invoice,
      params: {
        seller_name: "Updated Store",
        purchase_date: Date.current.to_s,
        items: [
          {
            product_name: "AC",
            brand: "LG",
            price: 35000,
            item_warranties: [ { component_name: "compressor", duration_months: 60 } ]
          }
        ]
      }
    )

    assert_predicate result, :success?
    assert_equal "Updated Store", invoice.reload.seller_name
    assert_equal 1, invoice.invoice_items.count
    assert_equal "AC", invoice.invoice_items.first.product_name
    assert_equal "LG", invoice.invoice_items.first.brand
    assert_equal 1, invoice.invoice_items.first.item_warranties.count
    assert_equal "compressor", invoice.invoice_items.first.item_warranties.first.component_name
  end

  test "returns error when validation fails" do
    invoice = create_invoice_with_item

    result = Invoices::Update.call(
      invoice: invoice,
      params: {
        seller_name: nil,
        items: []
      }
    )

    refute_predicate result, :success?
    assert_not_nil result.error
  end

  test "does not create duplicate warranty when updating non-warranty fields with legacy warranty_duration" do
    invoice = create_invoice_with_item
    original_warranty = invoice.invoice_items.first.item_warranties.first

    result = Invoices::Update.call(
      invoice: invoice,
      params: {
        seller_name: "Another Seller",
        warranty_duration: original_warranty.duration_months,
        product_name: invoice.invoice_items.first.product_name,
        brand: invoice.invoice_items.first.brand
      }
    )

    assert_predicate result, :success?
    invoice.reload
    assert_equal "Another Seller", invoice.seller_name
    assert_equal 1, invoice.invoice_items.first.item_warranties.count
    assert_equal original_warranty.id, invoice.invoice_items.first.item_warranties.first.id
  end

  test "updates existing warranty duration from legacy warranty_duration without creating a new warranty" do
    invoice = create_invoice_with_item
    existing_warranty = invoice.invoice_items.first.item_warranties.first

    result = Invoices::Update.call(
      invoice: invoice,
      params: {
        warranty_duration: 24,
        product_name: invoice.invoice_items.first.product_name,
        brand: invoice.invoice_items.first.brand
      }
    )

    assert_predicate result, :success?
    invoice.reload

    updated_warranty = invoice.invoice_items.first.item_warranties.first
    assert_equal 1, invoice.invoice_items.first.item_warranties.count
    assert_equal existing_warranty.id, updated_warranty.id
    assert_equal 24, updated_warranty.duration_months
  end

  test "triggers reminder reschedule and product broadcast after update" do
    invoice = create_invoice_with_item
    touched_item = invoice.invoice_items.first

    handled_items = []
    notifications = []
    broadcasts = []

    result = nil
    NotificationService.stub(:handle_warranty_update, ->(item) { handled_items << item.id }) do
      NotificationService.stub(:create_product_updated_notification, ->(user, updated_invoice) { notifications << [ user.id, updated_invoice.id ] }) do
        ProductBroadcastService.stub(:broadcast_update_to, ->(user, payload) { broadcasts << [ user.id, payload ] }) do
          result = Invoices::Update.call(
            invoice: invoice,
            params: {
              seller_name: "Updated Seller",
              items: [
                {
                  id: touched_item.id,
                  product_name: touched_item.product_name,
                  brand: touched_item.brand
                }
              ]
            }
          )
        end
      end
    end

    assert_predicate result, :success?
    assert_includes handled_items, touched_item.id
    assert_includes notifications, [ invoice.user.id, invoice.id ]
    assert_equal invoice.id, broadcasts.first.last[:invoice_id]
  end

  private

  def create_user
    User.create!(
      email: "inv-update-test-#{SecureRandom.hex(4)}@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )
  end

  def create_invoice_with_item
    user = create_user
    invoice = Invoice.create!(
      user: user,
      seller_name: "Store",
      purchase_date: Date.current,
      status: :processed,
      ocr_status: :completed
    )
    item = InvoiceItem.create!(
      invoice: invoice,
      product_name: "TV",
      brand: "Sony",
      price: 20000
    )
    ItemWarranty.create!(
      invoice_item: item,
      component_name: "product",
      duration_months: 12
    )
    invoice
  end
end
