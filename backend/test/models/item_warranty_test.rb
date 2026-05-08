# frozen_string_literal: true

require "test_helper"

class ItemWarrantyTest < ActiveSupport::TestCase
  test "normalized invoice and invoice item associations are exposed" do
    assert_equal :invoice_items, Invoice.reflect_on_association(:invoice_items).name
    assert_equal :warranties, Invoice.reflect_on_association(:warranties).name
    assert_includes Invoice.nested_attributes_options, :invoice_items
    assert_equal "total_amount", Invoice.attribute_aliases["amount"]

    assert_equal :item_warranties, InvoiceItem.reflect_on_association(:item_warranties).name
    assert_equal :warranties, InvoiceItem.reflect_on_association(:warranties).name
  end

  test "is valid with an invoice item, component_name, and duration_months" do
    user = User.create!(
      email: "test@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )

    invoice = Invoice.create!(
      user: user,
      seller: "Store",
      purchase_date: Date.current,
      status: :draft,
      ocr_status: :completed
    )

    item = InvoiceItem.create!(
      invoice: invoice,
      product_name: "TV",
      brand: "Sony"
    )

    warranty = ItemWarranty.new(
      invoice_item: item,
      component_name: "product",
      duration_months: 24
    )

    assert_predicate warranty, :valid?
  end

  test "item warranty requires component names to be unique per invoice item" do
    user = User.create!(
      email: "unique-test@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )

    invoice = Invoice.create!(
      user: user,
      seller: "Store",
      purchase_date: Date.current,
      status: :draft,
      ocr_status: :completed
    )

    item = InvoiceItem.create!(
      invoice: invoice,
      product_name: "TV",
      brand: "Sony"
    )

    ItemWarranty.create!(
      invoice_item: item,
      component_name: "product",
      duration_months: 24
    )

    duplicate = ItemWarranty.new(
      invoice_item: item,
      component_name: "product",
      duration_months: 12
    )

    refute_predicate duplicate, :valid?
    assert_includes duplicate.errors[:component_name], "has already been taken"
  end
end
