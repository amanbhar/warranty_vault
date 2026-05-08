# frozen_string_literal: true

require "test_helper"

class WarrantyMailerTest < ActionMailer::TestCase
  setup do
    @user = User.create!(
      email: "member@example.com",
      password: "password123",
      first_name: "Mira"
    )

    @invoice = Invoice.create!(
      user: @user,
      purchase_date: Date.new(2025, 5, 1),
      status: :draft
    )

    @item = @invoice.invoice_items.create!(
      product_name: "LG WashTower",
      brand: "LG"
    )

    @warranty = @item.item_warranties.create!(
      component_name: "compressor",
      duration_months: 12
    )
  end

  test "warranty_expiring_soon uses urgent copy for warranties expiring within a week" do
    mail = WarrantyMailer.with(
      user: @user,
      invoice: @invoice,
      item: @item,
      warranty: @warranty,
      days_remaining: 5
    ).warranty_expiring_soon

    body = mail.body.encoded

    assert_includes body, "Hi Mira"
    assert_includes body, "Your LG WashTower warranty is almost over."
    assert_includes body, "Compressor coverage expires in 5 days"
    assert_includes body, "Expires on May 01, 2026"
    assert_includes body, 'class="button">View Warranty</a>'
    assert_includes body, 'href="http://localhost:3000/invoices/'
  end

  test "warranty_expiring_soon uses heads-up copy for later reminders" do
    mail = WarrantyMailer.with(
      user: @user,
      invoice: @invoice,
      item: @item,
      warranty: @warranty,
      days_remaining: 21
    ).warranty_expiring_soon

    body = mail.body.encoded

    assert_includes body, "Just a heads up"
    assert_includes body, "Compressor coverage expires in 21 days"
  end

  test "warranty_expired mentions the expiry date and renewal guidance" do
    mail = WarrantyMailer.with(
      user: @user,
      invoice: @invoice,
      item: @item,
      warranty: @warranty
    ).warranty_expired

    body = mail.body.encoded

    assert_includes body, "Hi Mira"
    assert_includes body, "Your warranty for LG WashTower expired on May 01, 2026."
    assert_includes body, "If you bought an extended warranty, upload it and we&#39;ll keep tracking it for you."
    assert_includes body, 'class="button">Open Vault</a>'
    assert_includes body, 'href="http://localhost:3000/invoices/'
    assert_includes body, "http://localhost:3000/settings/notifications"
  end
end
