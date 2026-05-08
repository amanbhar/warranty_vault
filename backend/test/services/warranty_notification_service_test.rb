# frozen_string_literal: true

require "test_helper"

class WarrantyNotificationServiceTest < ActiveSupport::TestCase
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
      product_name: "LG Washing Machine",
      brand: "LG",
      purchase_date: Date.current,
      warranty_duration: 24,
      ocr_status: :completed
    )

    @warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "motor",
      warranty_months: 24,
      expires_at: 30.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )
  end

  test "should send reminder with both in-app and email notifications" do
    service = WarrantyNotificationService.new(@warranty)
    result = service.send_reminder

    assert result[:success]
    assert result[:in_app]
    assert result[:email]

    # Check notification created
    notification = Notification.find_by(user: @user, notification_type: :warranty_expiring)
    assert notification.present?
    assert notification.title.present?
    assert notification.message.present?
  end

  test "should create in-app notification with correct metadata" do
    service = WarrantyNotificationService.new(@warranty)
    service.create_in_app_notification

    notification = Notification.find_by(user: @user)
    assert notification.present?
    assert_equal @warranty.id, notification.metadata["warranty_id"]
    assert_equal @invoice.id, notification.metadata["invoice_id"]
    assert notification.metadata["days_remaining"].present?
    assert notification.action_url.include?(@invoice.id.to_s)
  end

  test "should queue email notification" do
    service = WarrantyNotificationService.new(@warranty)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    service.queue_email_notification

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
  end

  test "should build appropriate title based on days remaining" do
    # Urgent (<= 7 days)
    @warranty.update!(expires_at: 5.days.from_now)
    service = WarrantyNotificationService.new(@warranty)
    notification = service.create_in_app_notification
    assert Notification.find_by(user: @user).title.include?("Urgent")

    # Soon (<= 14 days)
    @warranty.update!(expires_at: 10.days.from_now, reminder_sent: false)
    service = WarrantyNotificationService.new(@warranty)
    service.create_in_app_notification
    assert Notification.where(user: @user).last.title.include?("Soon")

    # Normal (> 14 days)
    @warranty.update!(expires_at: 25.days.from_now, reminder_sent: false)
    service = WarrantyNotificationService.new(@warranty)
    service.create_in_app_notification
    assert Notification.where(user: @user).last.title.include?("Reminder")
  end

  test "should send expired notification" do
    @warranty.update!(expires_at: 5.days.ago)
    service = WarrantyNotificationService.new(@warranty)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    service.send_expired_notification

    notification = Notification.find_by(user: @user, notification_type: :warranty_expired)
    assert notification.present?
    assert notification.title.include?("Expired")
  end

  test "should send upload notification" do
    service = WarrantyNotificationService.new(@warranty)
    service.send_upload_notification

    notification = Notification.find_by(user: @user, notification_type: :upload_successful)
    assert notification.present?
    assert notification.message.include?("warranty")
  end

  test "class method send_reminder_for should send reminder" do
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    WarrantyNotificationService.send_reminder_for(@warranty)

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
  end

  test "class method send_bulk_reminders should process multiple warranties" do
    warranty2 = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "compressor",
      warranty_months: 12,
      expires_at: 25.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    result = WarrantyNotificationService.send_bulk_reminders(
      ProductWarranty.where(invoice: @invoice)
    )

    assert result[:success] >= 1
  end
end
