# frozen_string_literal: true

require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "notification_email renders content inside the shared layout" do
    user = User.create!(
      email: "alerts@example.com",
      password: "password123",
      first_name: "Ava"
    )

    mail = NotificationMailer.notification_email(
      user,
      "Coverage Update",
      "Your warranty status changed.",
      "https://frontend.example/invoices/42"
    )

    body = mail.body.encoded

    assert_equal [ "alerts@example.com" ], mail.to
    assert_equal "Coverage Update", mail.subject
    assert_includes body, "<h2>Coverage Update</h2>"
    assert_includes body, "<p>Your warranty status changed.</p>"
    assert_includes body, 'class="cta-container"'
    assert_includes body, 'class="button">View Product Details</a>'
    assert_includes body, "https://frontend.example/invoices/42"
    assert_includes body, "http://localhost:3000/dashboard"
    assert_includes body, "http://localhost:3000/settings/notifications"
    assert_not_includes body, "Your Warranty Tracking Assistant"
    assert_not_includes body, "background: linear-gradient(135deg, #3b82f6, #1d4ed8);"
  end

  test "invoice_uploaded greets with the email fallback and links to the product" do
    user = User.create!(
      email: "sam@example.com",
      password: "password123",
      first_name: nil
    )

    invoice = Invoice.create!(
      user: user,
      purchase_date: Date.new(2025, 4, 1),
      status: :draft
    )

    invoice.invoice_items.create!(
      product_name: "Dyson V15 Detect",
      brand: "Dyson"
    )

    mail = NotificationMailer.invoice_uploaded(user, invoice)
    body = mail.body.encoded

    assert_includes body, "Hi sam"
    assert_includes body, "Dyson V15 Detect is now in your Vault"
    assert_includes body, "We&#39;ll remind you before the warranty expires so you never miss it."
    assert_includes body, 'href="http://localhost:3000/invoices/'
    assert_includes body, 'class="button">View Product</a>'
    assert_includes body, "http://localhost:3000/settings/notifications"
  end
end
