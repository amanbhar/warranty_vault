# frozen_string_literal: true

require "test_helper"

class InvoiceScanServiceTest < ActiveSupport::TestCase
  test "download_file supports ActionDispatch uploaded files" do
    tempfile = Tempfile.new([ "invoice-upload", ".pdf" ])
    tempfile.binmode
    tempfile.write("%PDF-1.4 sample")
    tempfile.rewind

    file = ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "sample.pdf",
      type: "application/pdf"
    )

    service = InvoiceScanService.new(file)
    file_path = service.send(:download_file)

    assert File.exist?(file_path)
    assert_equal "%PDF-1.4 sample", File.binread(file_path)
  ensure
    FileUtils.rm_f(file_path) if defined?(file_path) && file_path
    tempfile.close!
  end

  test "scan returns normalized payload with warnings array and item warranties" do
    file = Struct.new(:original_filename, :content_type, :size, :download).new(
      "invoice.txt",
      "image/jpeg",
      1024,
      "raw invoice"
    )

    service = InvoiceScanService.new(file)
    service.singleton_class.send(:define_method, :extract_text_from_file) { "invoice text" }
    service.singleton_class.send(:define_method, :extract_structured_data) do |_raw_text|
      {
        success: true,
        data: {
          "product_name" => "LG 1.5 Ton AC",
          "brand" => "LG",
          "seller_name" => "Croma",
          "purchase_date" => "2026-04-05",
          "price" => 45999,
          "model_number" => "LS-Q18YNZA",
          "category" => "Appliances",
          "invoice_number" => "INV-100245",
          "warranties" => [
            { "component_name" => "product", "warranty_months" => 12 },
            { "component_name" => "compressor", "warranty_months" => 120 }
          ]
        },
        scan_duration_ms: 18
      }
    end

    result = service.scan

    assert result[:success]
    assert_equal "LG 1.5 Ton AC", result.dig(:data, :items, 0, :product_name)
    assert_equal "Croma", result.dig(:data, :seller)
    assert_equal "INV-100245", result.dig(:data, :invoice_number)
    assert_equal 2, result.dig(:data, :items, 0, :warranties).length
    assert_equal [], result[:warnings]
  end

  test "scan consumes canonical ai contract with items warnings and missing fields" do
    file = Struct.new(:original_filename, :content_type, :size, :download).new(
      "invoice.pdf",
      "application/pdf",
      1024,
      "%PDF-1.4"
    )

    service = InvoiceScanService.new(file)
    service.singleton_class.send(:define_method, :extract_text_from_file) { "invoice text" }
    service.singleton_class.send(:define_method, :extract_structured_data) do |_raw_text|
      {
        success: true,
        data: {
          "seller_name" => "Reliance Digital",
          "platform_name" => "Amazon",
          "purchase_date" => "2026-04-06",
          "invoice_number" => "INV-9001",
          "product_price" => 12999,
          "currency" => "INR",
          "warnings" => [ "Warranty card not visible. Review extracted warranty terms." ],
          "missing_fields" => [],
          "product_name" => "Samsung Soundbar",
          "model" => "HW-B450",
          "brand" => "Samsung",
          "product_category" => "Electronics",
          "warranties" => [
            {
              "component" => "product",
              "duration_months" => 24,
              "warranty_type" => "manufacturer",
              "details" => "2 year manufacturer warranty"
            }
          ]
        },
        scan_duration_ms: 12
      }
    end

    result = service.scan

    assert result[:success]
    assert_equal "Reliance Digital", result.dig(:data, :seller)
    assert_equal "Reliance Digital", result.dig(:data, :seller_name)
    assert_equal "Amazon", result.dig(:data, :platform_name)
    assert_equal "INV-9001", result.dig(:data, :invoice_number)
    assert_equal "Samsung Soundbar", result.dig(:data, :items, 0, :product_name)
    assert_equal "HW-B450", result.dig(:data, :model)
    assert_equal "Electronics", result.dig(:data, :product_category)
    assert_equal 12999.0, result.dig(:data, :product_price)
    assert_equal "manufacturer", result.dig(:data, :items, 0, :warranties, 0, :warranty_type)
    assert_equal [ "Warranty card not visible. Review extracted warranty terms." ], result[:warnings]
  end
end
