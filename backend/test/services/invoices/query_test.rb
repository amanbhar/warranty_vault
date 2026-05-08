# frozen_string_literal: true

require "test_helper"

class Invoices::QueryTest < ActiveSupport::TestCase
  test "filters invoices by search query" do
    user = create_user
    create_invoice(user, seller_name: "Amazon", product_name: "TV")
    create_invoice(user, seller_name: "Flipkart", product_name: "AC")

    results = Invoices::Query.new(
      scope: user.invoices,
      params: { q: "Amaz" }
    ).call

    assert_equal 1, results.to_a.count
    assert_equal "Amazon", results.first.seller_name
  end

  test "returns invoices ordered by created_at desc" do
    user = create_user
    create_invoice(user, seller_name: "First")
    create_invoice(user, seller_name: "Second")

    results = Invoices::Query.new(
      scope: user.invoices,
      params: {}
    ).call

    assert_equal "Second", results.first.seller_name
  end

  test "filters by warranty status" do
    user = create_user
    active_invoice = create_invoice(user, seller_name: "Active Store")
    expired_invoice = create_invoice(user, seller_name: "Expired Store")

    # Force deterministic statuses for query filtering
    active_warranty = active_invoice.invoice_items.first.item_warranties.first
    active_warranty.update_column(:expires_at, 120.days.from_now.to_date)

    expired_warranty = expired_invoice.invoice_items.first.item_warranties.first
    expired_warranty.update_column(:expires_at, 10.days.ago.to_date)

    results = Invoices::Query.new(
      scope: user.invoices,
      params: { status: "active" }
    ).call

    assert_includes results.to_a.map(&:id), active_invoice.id
    refute_includes results.to_a.map(&:id), expired_invoice.id
  end

  test "status filter treats mixed warranties as active" do
    user = create_user
    invoice = create_invoice(user, seller_name: "Mixed Store")
    item = invoice.invoice_items.first

    active = item.item_warranties.first
    active.update_column(:expires_at, 120.days.from_now.to_date)

    expired = ItemWarranty.create!(
      invoice_item: item,
      component_name: "compressor",
      duration_months: 12
    )
    expired.update_column(:expires_at, 10.days.ago.to_date)

    active_results = Invoices::Query.new(
      scope: user.invoices,
      params: { status: "active" }
    ).call
    expired_results = Invoices::Query.new(
      scope: user.invoices,
      params: { status: "expired" }
    ).call

    assert_includes active_results.to_a.map(&:id), invoice.id
    refute_includes expired_results.to_a.map(&:id), invoice.id
  end

  private

  def create_user
    User.create!(
      email: "inv-query-test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
  end

  def create_invoice(user, seller_name:, product_name: "Product")
    invoice = Invoice.create!(
      user: user,
      seller_name: seller_name,
      purchase_date: Date.current,
      status: :draft,
      ocr_status: :completed
    )
    item = InvoiceItem.create!(
      invoice: invoice,
      product_name: product_name,
      brand: "Brand"
    )
    ItemWarranty.create!(
      invoice_item: item,
      component_name: "product",
      duration_months: 24
    )
    invoice.reload
  end
end
