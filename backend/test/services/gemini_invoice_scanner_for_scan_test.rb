# frozen_string_literal: true

require "test_helper"

class GeminiInvoiceScannerForScanTest < ActiveSupport::TestCase
  test "prompt asks for canonical invoice scan json contract" do
    scanner = GeminiInvoiceScannerForScan.allocate
    scanner.instance_variable_set(:@raw_text, "invoice text")

    prompt = scanner.send(:build_strict_json_prompt)

    assert_includes prompt, '"seller_name"'
    assert_includes prompt, '"platform_name"'
    assert_includes prompt, '"product_price"'
    assert_includes prompt, '"product_category"'
    assert_includes prompt, '"warranties"'
    assert_includes prompt, '"missing_fields"'
    assert_includes prompt, '"warnings"'
    assert_includes prompt, "invoice text"
  end

  test "process normalizes array responses into invoice-level hash with items" do
    scanner = GeminiInvoiceScannerForScan.allocate
    scanner.instance_variable_set(:@raw_text, "invoice text")
    scanner.define_singleton_method(:make_gemini_request) do |_prompt|
      {
        success: true,
        response: [
          {
            product_name: "LG 12V SW LGS1600",
            model: "LGS1600",
            brand: "LG",
            invoice_number: "S363/24-25",
            purchase_date: "2026-04-07",
            product_price: "7116.95",
            seller_name: "SHREENATHJI LUBRICANTS",
            platform_name: "Other",
            warranties: [],
            product_category: "Electronics",
            missing_fields: [],
            warnings: []
          },
          {
            product_name: "LG-12V 200AH IT 2060TT(36+24)",
            model: "2060TT",
            brand: "LG",
            invoice_number: "S363/24-25",
            purchase_date: "2026-04-07",
            product_price: "11798.79",
            seller_name: "SHREENATHJI LUBRICANTS",
            platform_name: "Other",
            warranties: [ { component: "product", duration_months: 60 } ],
            product_category: "Electronics",
            missing_fields: [],
            warnings: []
          }
        ].to_json
      }
    end

    result = scanner.process

    assert result[:success], result[:error]
    assert_instance_of Hash, result[:data]
    assert_equal 2, result.dig(:data, "items").size
    assert_equal "SHREENATHJI LUBRICANTS", result.dig(:data, "seller_name")
    assert_equal "S363/24-25", result.dig(:data, "invoice_number")
    assert_equal "LG 12V SW LGS1600", result.dig(:data, "items", 0, "product_name")
    assert_equal "LG-12V 200AH IT 2060TT(36+24)", result.dig(:data, "items", 1, "product_name")
  end
end
