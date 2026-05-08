# frozen_string_literal: true

# Gemini Invoice Scanner for Scan-Then-Confirm Flow
#
# Purpose:
# - Processes raw text (not invoice objects) for the scan API
# - Returns ONLY strict JSON - no markdown, no explanations
# - Used by InvoiceScanService
#
# Usage:
#   scanner = GeminiInvoiceScannerForScan.new(raw_text)
#   result = scanner.process
class GeminiInvoiceScannerForScan
  class GeminiError < StandardError; end

  MODEL = Rails.application.config.ai_services.gemini_model
  TEMPERATURE = 0.1
  MAX_TOKENS = 8000
  TIMEOUT = 40

  attr_reader :raw_text, :client

  def initialize(raw_text)
    @raw_text = raw_text
    @client = build_client
  end

  def process
    Rails.logger.info "[GeminiScannerForScan] Starting extraction with #{MODEL}"

    prompt = build_strict_json_prompt
    result = make_gemini_request(prompt)
    if result[:success]
      begin
        parsed_data = normalize_parsed_payload(JSON.parse(result[:response]))
        unless parsed_data.is_a?(Hash)
          Rails.logger.error "[GeminiScannerForScan] Parsed response is not a JSON object"
          return { success: false, error: "Invalid AI response format" }
        end

        Rails.logger.info "[GeminiScannerForScan] Extraction and parsing successful"
        { success: true, data: parsed_data }
      rescue JSON::ParserError => e
        Rails.logger.error "[GeminiScannerForScan] JSON parse failed: #{e.message}"
        Rails.logger.debug "[GeminiScannerForScan] Raw response was: #{result[:response]}"

        salvaged = attempt_json_salvage(result[:response].to_s)
        return { success: true, data: salvaged } if salvaged.is_a?(Hash)

        { success: false, error: "Invalid AI response format" }
      end
    else
      # This triggers if the API call itself failed (timeout, auth, etc.)
      Rails.logger.error "[GeminiScannerForScan] API error: #{result[:error]}"
      { success: false, error: result[:error] }
    end
  rescue => e
    # Global fallback for unexpected system errors
    Rails.logger.error "[GeminiScannerForScan] Processing error: #{e.message}"
    { success: false, error: "Extraction failed: #{e.message}" }
  end

  private

  def build_client
    api_key = ENV.fetch("GEMINI_API_KEY", nil)
    raise GeminiError, "GEMINI_API_KEY not configured" unless api_key

    ENV["GOOGLE_API_KEY"] = api_key
    Google::Genai::Client.new
  rescue => e
    raise GeminiError, "Failed to initialize Gemini client: #{e.message}"
  end

  def build_strict_json_prompt
    <<~PROMPT
      You are an invoice data extractor. From OCR text, extract ONE main purchased product and return JSON.

      {
      "product_name": null,
      "model": null,
      "brand": null,
      "invoice_number": null,
      "purchase_date": null,
      "product_price": null,
      "seller_name": null,
      "platform_name": null,
      "warranties": [
        {
          "component": "product | compressor | panel | motor | battery | parts | labour | screen | other",
          "duration_months": 12,
          "details": "original warranty text"
        }
      ],
      "product_category": null,
      "missing_fields": [],
      "warnings": []
      }

      Rules:

      Output only JSON.
      First identify sections containing real product titles (ignore sections with only fees, charges, credit/debit notes, services).
      A valid product must have name + price.
      If multiple products exist, return all of them.
      purchase_date
      product_price: fetch total price and keep that price in both the record on multiple product case.
      The product price should only be an integer and not include any characters or symbols.
      seller_name = Sold By / Merchant.
      platform_name = Flipkart, Amazon, Croma, Reliance Digital, or Other.
      model = exact model if present.
      warranties: extract ALL warranty entries mentioned anywhere in the invoice.
      For each warranty, return a structured object with:
      - component: the part covered. Use exactly one of:
      "product" (whole product/comprehensive), "compressor", "panel", "motor",
      "battery", "parts", "labour", "screen". If unsure, use "product".
      - duration_months: integer, convert years to months (1 year = 12, 20 years = 240).
      - details: the original warranty text from the invoice.
      If an invoice mentions "1 year on product and 20 years on compressor",
      return TWO separate warranty objects, not one.
      Never return duplicate component names.
      product_category = mobile phone, Electronics, Appliances, Kitchenware, Furniture, Tools, Automotive, Other.
      Missing → null + add to missing_fields.
      If no valid product found → return all null + warning "no valid product found".

      OCR:
      #{raw_text}
    PROMPT
  end

  def make_gemini_request(prompt)
    Timeout.timeout(TIMEOUT) do
      response = client.models.generate_content(
        model: MODEL,
        contents: prompt,
        config: {
          temperature: TEMPERATURE,
          max_output_tokens: MAX_TOKENS,
          response_mime_type: "application/json"
        }
      )

      {
        success: true,
        response: response.text
      }
    rescue Timeout::Error
      { success: false, error: "AI request timeout" }
    rescue => e
      { success: false, error: "Gemini API error: #{e.message}" }
    end
  end

  def attempt_json_salvage(raw)
    return nil if raw.blank?

    repaired = close_open_json_structures(raw)
    begin
      parsed = normalize_parsed_payload(JSON.parse(repaired))
      return parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      # Fall through to trimming strategy below.
    end

    trimmed = raw.dup
    200.times do
      break if trimmed.blank?

      begin
        candidate = if trimmed.end_with?("}") || trimmed.end_with?("]")
                      trimmed
        elsif trimmed.end_with?('"') || trimmed.end_with?(",") || trimmed.match?(/[0-9A-Za-z\]]\z/)
                      "#{trimmed}}"
        else
                      trimmed
        end

        parsed = normalize_parsed_payload(JSON.parse(candidate))
        return parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        trimmed.chop!
      end
    end

    nil
  end

  def close_open_json_structures(raw)
    stack = []
    in_string = false
    escaped = false

    raw.each_char do |char|
      if in_string
        if escaped
          escaped = false
        elsif char == "\\"
          escaped = true
        elsif char == '"'
          in_string = false
        end
        next
      end

      case char
      when '"'
        in_string = true
      when "{"
        stack << "}"
      when "["
        stack << "]"
      when "}", "]"
        stack.pop if stack.last == char
      end
    end

    repaired = raw.rstrip.sub(/[,:]\s*\z/, "")
    repaired += '"' if in_string
    repaired + stack.reverse.join
  end

  def normalize_parsed_payload(parsed)
    case parsed
    when Hash
      parsed
    when Array
      normalize_array_payload(parsed)
    else
      nil
    end
  end

  def normalize_array_payload(entries)
    item_entries = entries.filter_map do |entry|
      next unless entry.is_a?(Hash)
      entry.deep_stringify_keys
    end
    return nil if item_entries.empty?

    first_item = item_entries.first
    {
      "seller_name" => first_present_value(item_entries, "seller_name", "seller"),
      "seller" => first_present_value(item_entries, "seller", "seller_name"),
      "platform_name" => first_present_value(item_entries, "platform_name"),
      "invoice_number" => first_present_value(item_entries, "invoice_number"),
      "purchase_date" => first_present_value(item_entries, "purchase_date"),
      "product_name" => first_item["product_name"],
      "brand" => first_item["brand"],
      "model" => first_item["model"] || first_item["model_number"],
      "product_price" => first_item["product_price"] || first_item["price"],
      "product_category" => first_item["product_category"] || first_item["category"],
      "warranties" => normalize_warranties(first_item["warranties"]),
      "warnings" => item_entries.flat_map { |item| Array(item["warnings"]) }.compact.uniq,
      "missing_fields" => item_entries.flat_map { |item| Array(item["missing_fields"]) }.compact.uniq,
      "items" => item_entries.map do |item|
        {
          "product_name" => item["product_name"],
          "brand" => item["brand"],
          "model" => item["model"] || item["model_number"],
          "model_number" => item["model_number"] || item["model"],
          "price" => item["product_price"] || item["price"],
          "product_price" => item["product_price"] || item["price"],
          "category" => item["product_category"] || item["category"],
          "product_category" => item["product_category"] || item["category"],
          "warranties" => normalize_warranties(item["warranties"]),
          "warnings" => Array(item["warnings"]),
          "missing_fields" => Array(item["missing_fields"])
        }.compact
      end
    }.compact
  end

  def first_present_value(entries, *keys)
    entries.each do |entry|
      keys.each do |key|
        value = entry[key]
        return value if value.present?
      end
    end
    nil
  end

  def normalize_warranties(raw_warranties)
    warranties = raw_warranties.is_a?(Array) ? raw_warranties : []
    warranties.map do |warranty|
      case warranty
      when Hash
        normalized = warranty.deep_stringify_keys
        normalized["component"] ||= normalized["component_name"]
        normalized["duration_months"] ||= normalized["warranty_months"]
        normalized
      when String
        { "details" => warranty, "component" => "product" }
      else
        nil
      end
    end.compact
  end
end
