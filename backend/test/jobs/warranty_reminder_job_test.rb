# frozen_string_literal: true

require "test_helper"

class WarrantyReminderJobTest < ActiveJob::TestCase
  include WarrantyTestHelpers

  setup do
    @user = User.create!(
      email: "test@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )

    @invoice = Invoice.create!(
      user: @user,
      product_name: "Samsung Refrigerator",
      brand: "Samsung",
      purchase_date: Date.current,
      warranty_duration: 12,
      ocr_status: :completed
    )

    @warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "compressor",
      warranty_months: 12,
      expires_at: 30.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )
  end

  test "should process warranty reminder successfully" do
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    WarrantyReminderJob.perform_now(@warranty.id)

    @warranty.reload
    assert @warranty.reminder_sent
    assert @warranty.last_reminder_sent_at.present?

    # Check notification was created
    notification = Notification.find_by(user: @user, notification_type: :warranty_expiring)
    assert notification.present?
    assert notification.title.include?("Warranty")
  end

  test "should skip if warranty not found" do
    assert_no_enqueued_jobs

    WarrantyReminderJob.perform_now(999_999)

    assert_no_enqueued_jobs
  end

  test "should skip if reminder already sent" do
    @warranty.update!(reminder_sent: true)

    assert_no_enqueued_jobs

    WarrantyReminderJob.perform_now(@warranty.id)

    assert_no_enqueued_jobs
  end

  test "should create in-app notification with correct data" do
    WarrantyReminderJob.perform_now(@warranty.id)

    notification = Notification.find_by(user: @user)
    assert notification.present?
    assert_equal :warranty_expiring, notification.notification_type
    assert notification.title.present?
    assert notification.message.present?
    assert notification.metadata["warranty_id"].present?
    assert notification.metadata["days_remaining"].present?
  end

  test "should queue email notification" do
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    WarrantyReminderJob.perform_now(@warranty.id)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
  end

  test "should handle expired warranty" do
    @warranty.update!(expires_at: 10.days.ago)

    WarrantyReminderJob.perform_now(@warranty.id)

    @warranty.reload
    assert @warranty.reminder_sent

    notification = Notification.find_by(user: @user)
    assert notification.title.include?("Expired")
  end

  test "should handle warranty expiring within 7 days (urgent)" do
    @warranty.update!(expires_at: 5.days.from_now)

    WarrantyReminderJob.perform_now(@warranty.id)

    notification = Notification.find_by(user: @user)
    assert notification.title.include?("Urgent")
  end
end
