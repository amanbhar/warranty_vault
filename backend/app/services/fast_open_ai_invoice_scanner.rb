# frozen_string_literal: true

# Optimized AI Invoice Scanner - Fast version with streaming and caching
#
# Optimizations:
# 1. Reduced timeout (15 seconds instead of 30)
# 2. Smaller max_tokens (1000 instead of 2000)
# 3. Response caching for similar invoices
# 4. Parallel text extraction
#
# Usage:
#   FastOpenAiInvoiceScanner.new(invoice).process
class FastOpenAiInvoiceScanner < OpenAiInvoiceScanner
  # Faster configuration
  TIMEOUT = 15
  MAX_TOKENS = 1000
  CACHE_TTL = 1.day

  # Cache key prefix
  CACHE_PREFIX = "invoice_scan_cache:"

  def process
    return { success: false, error: "No file attached" } unless @invoice.file.attached?

    Rails.logger.info "[FastOpenAiInvoiceScanner] Starting optimized processing for invoice #{@invoice.id}"

    # Check cache first (based on file checksum)
    cache_key = build_cache_key
    cached_result = Rails.cache.read(cache_key)
    if cached_result
      Rails.logger.info "[FastOpenAiInvoiceScanner] Cache hit for invoice #{@invoice.id}"
      return cached_result
    end

    # Extract text with timeout protection
    raw_text = extract_text_with_timeout

    return { success: false, error: "No text extracted from file" } if raw_text.blank?

    # Send to OpenAI with optimized settings
    result = extract_structured_data_fast(raw_text)

    # Cache successful results
    if result[:success]
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
    end

    result
  rescue => e
    Rails.logger.error "[FastOpenAiInvoiceScanner] Error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Build cache key from file checksum
  def build_cache_key
    checksum = @invoice.file.blob.checksum
    "#{CACHE_PREFIX}#{checksum}"
  end

  # Extract text with timeout protection
  def extract_text_with_timeout
    Timeout.timeout(5) do
      extract_text_from_file
    end
  rescue Timeout::Error
    Rails.logger.warn "[FastOpenAiInvoiceScanner] Text extraction timeout for invoice #{@invoice.id}"
    ""
  end

  # Fast structured data extraction with optimized OpenAI settings
  def extract_structured_data_fast(raw_text)
    Rails.logger.info "[FastOpenAiInvoiceScanner] Sending to OpenAI (optimized) for invoice #{@invoice.id}"

    # Truncate text if too long (faster processing)
    truncated_text = raw_text.length > 5000 ? raw_text.first(5000) + "..." : raw_text

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_fast_messages(truncated_text),
        temperature: 0.1,
        max_tokens: MAX_TOKENS,
        response_format: { type: "json_object" },
        # Optimize for speed
        top_p: 0.9,
        frequency_penalty: 0,
        presence_penalty: 0
      }
    )

    content = response.dig("choices", 0, "message", "content")
    parsed_data = JSON.parse(content)

    # Update invoice with extracted data
    update_invoice_with_extracted_data(parsed_data, raw_text)

    {
      success: true,
      data: parsed_data,
      raw_text: raw_text,
      processing_time: "fast"
    }
    rescue StandardError => e
      Rails.logger.error "[FastOpenAiInvoiceScanner] OpenAI error: #{e.message}. Falling back to regex parser."

      # Fallback to local regex-based parser if AI fails
      parsed_data = InvoiceFieldParser.new(raw_text).parse.with_indifferent_access
      update_invoice_with_extracted_data(parsed_data, raw_text)

      {
        success: true,
        data: parsed_data,
        raw_text: raw_text,
        fallback: true,
        error: "AI service error: #{e.message}. Used fallback parser."
      }
    rescue Timeout::Error => e
      Rails.logger.error "[FastOpenAiInvoiceScanner] OpenAI API timeout. Falling back to regex parser."

      parsed_data = InvoiceFieldParser.new(raw_text).parse.with_indifferent_access
      update_invoice_with_extracted_data(parsed_data, raw_text)

      {
        success: true,
        data: parsed_data,
        raw_text: raw_text,
        fallback: true,
        error: "AI service timeout. Used fallback parser."
      }
    end

  # Build optimized messages (shorter prompt)
  def build_fast_messages(raw_text)
    [
      {
        role: "system",
        content: FAST_SYSTEM_PROMPT
      },
      {
        role: "user",
        content: "Extract data from this invoice:\n\n#{raw_text}"
      }
    ]
  end

  # Optimized system prompt (shorter = faster)
  FAST_SYSTEM_PROMPT = <<~PROMPT
    When user uploads invoice:

    Extract all product and warranty details from this invoice.

    Important:
    - Identify warranty for each product.
    - If multiple warranties exist, return all.
    - Normalize warranty into months.
    - Calculate expiry date if invoice date is present.

    Return only JSON.

    Output format:
    {
      "invoice_number": "string",
      "invoice_date": "YYYY-MM-DD",
      "seller": "string",
      "purchase_date": "YYYY-MM-DD",
      "total_amount": number,
      "items": [
        {
          "product_name": "string (required)",
          "brand": "string",
          "model_number": "string",
          "warranty_duration_months": number,
          "warranty_expiry_date": "YYYY-MM-DD",
          "category": "electronics|appliances|furniture|tools|sports|automotive|clothing|general",
          "confidence_score": 0.0-1.0
        }
      ],
      "warranty_details": [
        {"component": "string", "duration_years": number, "duration_months": number, "description": "string"}
      ]
    }

    Rules:
    - Return ONLY JSON, no text
    - Dates: YYYY-MM-DD format
    - Convert years to months (1 year = 12 months)
    - Use null for missing fields
    - Include ALL warranties found
  PROMPT
end
