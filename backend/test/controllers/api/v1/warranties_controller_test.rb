# frozen_string_literal: true

require "test_helper"

class Api::V1::WarrantiesControllerTest < ActionDispatch::IntegrationTest
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
      product_name: "Samsung TV",
      brand: "Samsung",
      purchase_date: Date.current,
      warranty_duration: 12,
      ocr_status: :completed
    )

    @warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "display",
      warranty_months: 12,
      expires_at: 45.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    # Generate a valid JWT token for authentication
    @token = JWT.encode(
      { user_id: @user.id, exp: 24.hours.from_now.to_i },
      Rails.application.secret_key_base
    )
  end

  test "should get index of warranties" do
    get api_v1_warranties_path,
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    assert json["data"].present?
    assert json["meta"].present?
    assert_equal 1, json["data"].size
  end

  test "should get expiring warranties" do
    get expiring_api_v1_warranties_path,
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    assert json["data"].present?
    assert json["meta"].present?
    assert_equal 30, json["meta"]["days"]
  end

  test "should get warranty stats" do
    get stats_api_v1_warranties_path,
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    assert json["data"].present?
    assert json["data"]["total"].present?
    assert json["data"]["active"].present?
    assert json["data"]["by_component"].present?
  end

  test "should trigger manual reminder for warranty" do
    post remind_api_v1_warranty_path(@warranty),
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    assert json["success"]
    assert_equal "Reminder scheduled successfully", json["message"]
  end

  test "should not allow reminding non-existent warranty" do
    post remind_api_v1_warranty_path(999_999),
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :not_found
  end

  test "should not allow accessing another user's warranty" do
    other_user = User.create!(
      email: "other@example.com",
      password_digest: BCrypt::Password.create("password123")
    )

    other_invoice = Invoice.create!(
      user: other_user,
      product_name: "Other Product",
      brand: "Other Brand",
      purchase_date: Date.current,
      warranty_duration: 12,
      ocr_status: :completed
    )

    other_warranty = ProductWarranty.create!(
      invoice: other_invoice,
      component_name: "product",
      warranty_months: 12,
      expires_at: 30.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    post remind_api_v1_warranty_path(other_warranty),
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :not_found
  end

  test "should bulk remind multiple warranties" do
    warranty2 = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "battery",
      warranty_months: 6,
      expires_at: 25.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    post bulk_remind_api_v1_warranties_path,
         params: { warranty_ids: [ @warranty.id, warranty2.id ] },
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    assert json["success"]
    assert_equal 2, json["data"]["success_count"]
  end

  test "should require authentication for warranty endpoints" do
    get api_v1_warranties_path
    assert_response :unauthorized

    get expiring_api_v1_warranties_path
    assert_response :unauthorized

    post remind_api_v1_warranty_path(@warranty)
    assert_response :unauthorized
  end

  test "should filter warranties by component" do
    get api_v1_warranties_path(component: "display"),
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    json["data"].each do |warranty|
      assert_equal "Display", warranty["component_name"]
    end
  end

  test "should filter active warranties" do
    get api_v1_warranties_path(status: "active"),
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    json = JSON.parse(response.body)

    json["data"].each do |warranty|
      assert_equal "active", warranty["status"]
    end
  end
end
