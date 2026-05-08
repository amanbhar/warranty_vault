# frozen_string_literal: true

require "test_helper"

class WarrantyReminderServiceTest < ActiveSupport::TestCase
  include WarrantyTestHelpers

  setup do
    @user = User.create!(
      email: "test@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User",
      email_verified: true
    )

    @invoice = Invoice.create!(
      user: @user,
      seller: "Test Seller",
      product_name: "Test Product",
      brand: "Test Brand",
      purchase_date: Date.current,
      warranty_duration: 12,
      status: :draft,
      ocr_status: :completed
    )

    @warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "product",
      warranty_months: 12,
      expires_at: 60.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    clear_enqueued_jobs
  end

  test "should schedule reminder for future date" do
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder

    assert_enqueued_jobs 3
  end

  test "should send immediate reminder if expiry is within 30 days" do
    @warranty.update!(expires_at: 20.days.from_now)
    clear_enqueued_jobs
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder

    assert_enqueued_jobs 3
  end

  test "should not schedule if reminder already sent" do
    %w[thirty_days seven_days expiry_day].each do |milestone|
      Notification.create!(
        user: @user,
        title: "Existing",
        message: "Existing",
        notification_type: :warranty_expiring,
        metadata: { warranty_id: @warranty.id, milestone: milestone }
      )
    end
    clear_enqueued_jobs
    service = WarrantyReminderService.new(@warranty)

    assert_equal 0, service.schedule_reminder
    assert_no_enqueued_jobs
  end

  test "should not schedule if expires_at is nil" do
    @warranty.update!(expires_at: nil)
    clear_enqueued_jobs
    service = WarrantyReminderService.new(@warranty)

    assert_equal 0, service.schedule_reminder
    assert_no_enqueued_jobs
  end

  test "should send immediate reminder if expiry date is in past" do
    @warranty.update!(expires_at: 10.days.ago)
    clear_enqueued_jobs
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder
    assert_enqueued_jobs 3
  end

  test "should reschedule reminder" do
    @warranty.update!(reminder_sent: true)
    clear_enqueued_jobs
    service = WarrantyReminderService.new(@warranty)

    service.reschedule_reminder

    @warranty.reload
    refute @warranty.reminder_sent
    assert_enqueued_jobs 3
  end

  test "class method schedule_for_invoice should schedule all warranties" do
    warranty2 = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "battery",
      warranty_months: 6,
      expires_at: 45.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )
    clear_enqueued_jobs

    WarrantyReminderService.schedule_for_invoice(@invoice)

    # Should schedule 30-day, 7-day, and expiry reminders for each warranty
    assert_enqueued_jobs 6
  end

  test "class method process_due_reminders should process warranties due for reminder" do
    # Create warranty due for reminder
    due_warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "motor",
      warranty_months: 1,
      expires_at: 30.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )
    clear_enqueued_jobs

    count = WarrantyReminderService.process_due_reminders

    assert count >= 1
  end
end
