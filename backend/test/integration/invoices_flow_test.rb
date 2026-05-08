# frozen_string_literal: true

require "test_helper"

class InvoicesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "flow@example.com",
      password: "password123",
      first_name: "Flow",
      last_name: "User",
      email_verified: true
    )
    @token = @user.generate_jwt
  end

  test "create accepts reviewed flat payload and persists invoice item, warranties, and raw ai data" do
    clear_enqueued_jobs

    assert_difference("Invoice.count", 1) do
      assert_difference("InvoiceItem.count", 1) do
        assert_difference("Warranty.count", 2) do
          assert_difference("ProductWarranty.count", 2) do
            assert_enqueued_jobs 6, only: WarrantyReminderJob do
              post "/api/v1/invoices",
                   params: {
                     invoice: {
                       seller: "Croma",
                       purchase_date: "2026-04-05",
                       amount: "45999",
                       invoice_number: "INV-100245",
                       raw_ai_data: {
                         source: "scan",
                         warnings: [ "Warranty details detected from multiple lines" ]
                       },
                       product_name: "LG 1.5 Ton AC",
                       brand: "LG",
                       model_number: "LS-Q18YNZA",
                       category: "Appliances",
                       warranties: [
                         { component: "product", duration_months: 12 },
                         { component: "compressor", duration_months: 120 }
                       ]
                     }
                   },
                   headers: authenticated_headers(@token)
            end
          end
        end
      end
    end

    assert_response :created

    body = JSON.parse(response.body)
    invoice = Invoice.order(:id).last

    assert_equal "LG 1.5 Ton AC", invoice.product_name
    assert_equal "LG", invoice.brand
    assert_equal "Croma", invoice.seller
    assert_equal "INV-100245", invoice.invoice_number
    assert_equal "scan", invoice.raw_ai_data["source"]

    first_item = invoice.invoice_items.first
    assert_equal "LG 1.5 Ton AC", first_item.product_name
    assert_equal 2, first_item.warranties.count
    assert_equal %w[compressor product], first_item.warranties.order(:component).pluck(:component)

    assert_equal 2, invoice.product_warranties.count
    assert_equal %w[compressor product], invoice.product_warranties.order(:component_name).pluck(:component_name)

    assert_equal 1, body.dig("invoice", "items").length
    assert_equal 2, body.dig("invoice", "items", 0, "warranties").length
  end

  test "create accepts edited gemini response payload directly" do
    clear_enqueued_jobs

    extracted_data = {
      seller_name: "Utkrisht Trade Solutions Pvt Ltd",
      platform_name: "Flipkart",
      purchase_date: "2026-03-05",
      invoice_number: "FK-INV-20260305",
      product_name: "Motorola g45 5G",
      model: "g45 5G",
      brand: "Motorola",
      product_price: 10849.0,
      product_category: "Handsets",
      warranties: [
        {
          component: "handset",
          duration_months: 12,
          warranty_type: "manufacturer",
          details: "1 Year Warranty on Handset"
        },
        {
          component: "accessories",
          duration_months: 6,
          warranty_type: "manufacturer",
          details: "6 Months Warranty on Accessories"
        }
      ],
      warnings: [],
      missing_fields: []
    }

    assert_difference("Invoice.count", 1) do
      assert_difference("InvoiceItem.count", 1) do
        assert_difference("Warranty.count", 2) do
          assert_difference("ProductWarranty.count", 2) do
            assert_enqueued_jobs 6, only: WarrantyReminderJob do
              post "/api/v1/invoices",
                   params: {
                     invoice: {
                       extracted_data: extracted_data,
                       raw_ai_data: extracted_data
                     }
                   },
                   headers: authenticated_headers(@token)
            end
          end
        end
      end
    end

    assert_response :created

    invoice = Invoice.order(:id).last
    first_item = invoice.invoice_items.first

    assert_equal "Utkrisht Trade Solutions Pvt Ltd", invoice.seller
    assert_equal "FK-INV-20260305", invoice.invoice_number
    assert_equal "Motorola g45 5G", invoice.product_name
    assert_equal "g45 5G", invoice.model_number
    assert_equal "Motorola", invoice.brand
    assert_equal "Handsets", invoice.category
    assert_equal "Flipkart", invoice.raw_ai_data["platform_name"]
    assert_equal "Motorola g45 5G", first_item.product_name
    assert_equal %w[accessories handset], first_item.warranties.order(:component).pluck(:component)
  end

  test "create accepts multi-item extracted payload and stores separate warranty records per item" do
    clear_enqueued_jobs

    extracted_data = {
      seller_name: "SHREENATHJI LUBRICANTS",
      platform_name: "Other",
      purchase_date: "2026-04-07",
      invoice_number: "S363-24-25-MULTI",
      product_category: "Electronics",
      items: [
        {
          product_name: "LG 12V SW LGS1600",
          model: "LGS1600",
          brand: "LG",
          product_price: 7116.95,
          warranties: [
            { component: "product", duration_months: 24 }
          ]
        },
        {
          product_name: "LG-12V 200AH IT 2060TT(36+24)",
          model: "2060TT",
          brand: "LG",
          product_price: 11798.79,
          warranties: [
            { component: "product", duration_months: 36 },
            { component: "battery", duration_months: 24 }
          ]
        }
      ],
      warnings: [],
      missing_fields: []
    }

    assert_difference("Invoice.count", 1) do
      assert_difference("InvoiceItem.count", 2) do
        assert_difference("Warranty.count", 3) do
          assert_difference("ProductWarranty.count", 3) do
            post "/api/v1/invoices",
                 params: {
                   invoice: {
                     extracted_data: extracted_data,
                     raw_ai_data: extracted_data
                   }
                 },
                 headers: authenticated_headers(@token)
          end
        end
      end
    end

    assert_response :created

    invoice = Invoice.order(:id).last
    assert_equal 2, invoice.invoice_items.count
    assert_equal 3, invoice.warranties.count
    assert_equal 3, invoice.product_warranties.count
  end

  test "create parses comma separated amount and stores full numeric value" do
    post "/api/v1/invoices",
         params: {
           invoice: {
             seller: "Croma",
             purchase_date: "2026-04-05",
             amount: "23,500",
             invoice_number: "INV-PRICE-23500",
             items: [
               {
                 product_name: "LG 12V SW LGS1600",
                 brand: "LG",
                 model_number: "LGS1600",
                 warranties: [
                   { component: "product", duration_months: "24" }
                 ]
               }
             ]
           }
         },
         headers: authenticated_headers(@token)

    assert_response :created
    invoice = Invoice.order(:id).last
    assert_equal 23500.0, invoice.total_amount.to_f
  end

  test "create rejects non-numeric amount and warranty duration" do
    post "/api/v1/invoices",
         params: {
           invoice: {
             seller: "Croma",
             purchase_date: "2026-04-05",
             amount: "23,500abc",
             invoice_number: "INV-INVALID-NUMERIC",
             items: [
               {
                 product_name: "LG 12V SW LGS1600",
                 brand: "LG",
                 model_number: "LGS1600",
                 warranties: [
                   { component: "product", duration_months: "24m" }
                 ]
               }
             ]
           }
         },
         headers: authenticated_headers(@token)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "Amount must be a valid number"
    assert_includes body["error"], "Warranty duration must be numeric"
  end
end
