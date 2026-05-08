# frozen_string_literal: true

require "test_helper"

class InvoiceScansFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "scan-flow@example.com",
      password: "password123",
      first_name: "Scan",
      last_name: "User",
      email_verified: true
    )
    @token = @user.generate_jwt
  end

  test "scan returns structured error when scanner returns a string error" do
    tempfile = Tempfile.new([ "scan-flow", ".pdf" ])
    tempfile.binmode
    tempfile.write("%PDF-1.4 sample")
    tempfile.rewind

    uploaded_file = Rack::Test::UploadedFile.new(tempfile.path, "application/pdf", original_filename: "sample.pdf")

    scan_service_singleton = class << InvoiceScanService; self; end
    original_scan_file = InvoiceScanService.method(:scan_file)

    scan_service_singleton.send(:define_method, :scan_file) do |_file|
      { success: false, error: "Response is not valid JSON" }
    end

    post "/api/v1/invoice_scans/scan",
         params: { file: uploaded_file },
         headers: authenticated_headers(@token)

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal "SCAN_FAILED", body.dig("error", "code")
    assert_equal "Response is not valid JSON", body.dig("error", "message")
  ensure
    if defined?(scan_service_singleton) && defined?(original_scan_file)
      scan_service_singleton.send(:define_method, :scan_file, original_scan_file)
    end
    tempfile.close!
  end
end
