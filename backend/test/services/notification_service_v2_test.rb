# frozen_string_literal: true

require "test_helper"

class NotificationServiceV2Test < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(
      email: "notification-v2-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User",
      email_verified: false
    )
    @user.user_reminder_preferences.create!(days_before_expiry: 14, reminder_type: :custom)

    @invoice = Invoice.create!(
      user: @user,
      seller_name: "Store",
      purchase_date: Date.current,
      status: :processed,
      ocr_status: :completed
    )

    @item = InvoiceItem.create!(
      invoice: @invoice,
      product_name: "Laptop",
      brand: "Dell",
      price: 50_000
    )

    @warranty = ItemWarranty.create!(
      invoice_item: @item,
      component_name: "main_unit",
      duration_months: 1,
      start_date: Date.current - 20.days
    )
  end

  test "handle_warranty_update regenerates default and custom reminders" do
    Reminder.create!(
      user: @user,
      invoice_item: @item,
      reminder_type: :default,
      remind_at: 3.days.from_now,
      sent: false
    )

    assert_difference -> { Reminder.where(user: @user, invoice_item: @item).count }, 3 do
      NotificationServiceV2.handle_warranty_update(@user, @item)
    end

    reminder_days = Reminder.where(user: @user, invoice_item: @item).pluck(:remind_at).map do |at|
      (@item.nearest_expiry_date - at.to_date).to_i
    end

    assert_includes reminder_days, 30
    assert_includes reminder_days, 7
    assert_includes reminder_days, 1
    assert_includes reminder_days, 14
  end

  test "handle_warranty_update enqueues immediate processing for in-range reminders" do
    @warranty.update!(start_date: Date.current - 31.days, duration_months: 1)
    clear_enqueued_jobs

    NotificationServiceV2.handle_warranty_update(@user, @item)

    assert_enqueued_jobs 4, only: ProcessSingleReminderJob
  end
end
