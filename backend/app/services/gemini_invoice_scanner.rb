# frozen_string_literal: true

# Gemini AI Invoice Scanner - Enhanced with strict extraction rules
#
# Improvements:
# 1. STRICT warranty extraction - ALWAYS extract if present
# 2. Multiple warranty detection - captures all component warranties
# 3. Model number fallback - uses product_name if model_number missing
# 4. Enhanced prompt with explicit rules and examples
# 5. Post-processing validation with regex fallbacks
# 6. Comprehensive logging for debugging
#
# Usage:
#   GeminiInvoiceScanner.new(invoice).process
class GeminiInvoiceScanner
  class GeminiError < StandardError; end
  class ConfigurationError < StandardError; end

  # Gemini model configuration from Rails config
  MODEL = Rails.application.config.ai_services.gemini_model
  TEMPERATURE = Rails.application.config.ai_services.gemini_temperature
  MAX_TOKENS = Rails.application.config.ai_services.gemini_max_tokens
  TIMEOUT = 30

  attr_reader :invoice, :client

  def initialize(invoice)
    @invoice = invoice
    @client = build_client
  end

  def process
    return { success: false, error: "No file attached" } unless @invoice.file.attached?

    Rails.logger.info "[GeminiInvoiceScanner] Starting processing for invoice #{@invoice.id}"

    # Extract text with timeout protection
    raw_text = extract_text_with_timeout
    return { success: false, error: "No text extracted from file" } if raw_text.blank?

    Rails.logger.info "[GeminiInvoiceScanner] Extracted #{raw_text.length} characters from invoice #{@invoice.id}"
    Rails.logger.info "[GeminiInvoiceScanner] OCR TEXT START"
    Rails.logger.info raw_text
    Rails.logger.info "[GeminiInvoiceScanner] OCR TEXT END"

    # Send to Gemini with ENHANCED structured prompt
    result = extract_structured_data_with_gemini(raw_text)

    # Post-processing validation and fallbacks
    if result[:success]
      result = post_process_and_validate(result, raw_text)

      if result[:success]
        # Update invoice with extracted data
        update_invoice_with_extracted_data(result[:data], raw_text)

        Rails.logger.info "[GeminiInvoiceScanner] Successfully processed multi-item invoice #{@invoice.id}"
        Rails.logger.info "  - Seller: #{result[:data]['seller']}"
        Rails.logger.info "  - Item count: #{result[:data]['items']&.count}"
      end
    else
      Rails.logger.error "[GeminiInvoiceScanner] Failed to process invoice #{@invoice.id}: #{result[:error]}"
    end

    result
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Error processing invoice #{@invoice.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  def self.scan_text(raw_text)
    scanner = new(nil)
    result = scanner.send(:extract_structured_data_with_gemini, raw_text)

    if result[:success]
      result = scanner.send(:post_process_and_validate, result, raw_text)
    end

    result
  end

  private

  # Build Gemini client
  def build_client
    # google-genai is manually loaded in config/initializers/google_genai.rb
    # to avoid a Zeitwerk naming conflict in the gem's own loader.

    api_key = ENV.fetch("GEMINI_API_KEY", nil)
    raise ConfigurationError, "GEMINI_API_KEY not configured" unless api_key

    # Set the API key in the environment for the gem to pick up
    ENV["GOOGLE_API_KEY"] = api_key

    client = Google::Genai::Client.new

    Rails.logger.info "[GeminiInvoiceScanner] Gemini client initialized with model: #{MODEL}"
    client
  rescue LoadError => e
    raise ConfigurationError, "google-genai gem not found: #{e.message}"
  rescue => e
    raise ConfigurationError, "Failed to initialize Gemini client: #{e.message}"
  end

  # Extract text with timeout protection
  def extract_text_with_timeout
    Timeout.timeout(TIMEOUT) do
      if @invoice.file.content_type.include?("pdf")
        extract_text_from_pdf
      elsif @invoice.file.content_type.include?("image")
        extract_text_from_image
      else
        extract_text_from_document
      end
    end
  rescue Timeout::Error
    Rails.logger.error "[GeminiInvoiceScanner] Text extraction timeout for invoice #{@invoice.id}"
    nil
  end

  # Extract text from PDF
  def extract_text_from_pdf
    require "pdf/reader"

    file_path = download_file
    reader = PDF::Reader.new(file_path)
    text = reader.pages.map(&:text).join("\n")
    text.strip
  rescue LoadError
    file_path = download_file
    File.read(file_path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "")
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from image using Google Vision
  def extract_text_from_image
    require "google/cloud/vision"

    file_path = download_file
    vision = Google::Cloud::Vision.new(
      project_id: ENV.fetch("GOOGLE_PROJECT_ID", "warranty-vault"),
      credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
    )

    image = vision.image file_path
    response = image.text
    response.text.strip
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from document
  def extract_text_from_document
    file_path = download_file
    File.read(file_path, encoding: "UTF-8").strip
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Download file to temp location
  def download_file
    file_path = Rails.root.join("tmp", "invoice_#{@invoice.id}_#{SecureRandom.uuid}")
    File.open(file_path, "wb") do |file|
      file.write(@invoice.file.download)
    end
    file_path
  end

  # Extract structured data with Gemini - ENHANCED PROMPT
  def extract_structured_data_with_gemini(raw_text)
    prompt = build_enhanced_gemini_prompt(raw_text)

    Rails.logger.info "[GeminiInvoiceScanner] Sending to Gemini with enhanced prompt"

    result = make_gemini_request(prompt)

    if result[:success]
      parsed_data = parse_gemini_response(result[:response_text])

      if parsed_data[:success]
        # Log AI response for debugging
        Rails.logger.info "[GeminiInvoiceScanner] AI RESPONSE:"
        Rails.logger.info result[:response_text]
        Rails.logger.info "[GeminiInvoiceScanner] PARSED DATA:"
        Rails.logger.info parsed_data[:data].inspect
      end

      parsed_data
    else
      result
    end
  end

  # Make request to Gemini with timeout
  def make_gemini_request(prompt)
    Timeout.timeout(TIMEOUT) do
      response = @client.models.generate_content(
        model: MODEL,
        contents: [ prompt ],
        config: {
          temperature: TEMPERATURE,
          maxOutputTokens: MAX_TOKENS,
          responseMimeType: "application/json"
        }
      )

      response_text = response.text

      if response_text.blank?
        Rails.logger.warn "[GeminiInvoiceScanner] Empty response from Gemini"
        return { success: false, error: "Empty response from Gemini" }
      end

      { success: true, response_text: response_text }
    end
  rescue Timeout::Error
    Rails.logger.error "[GeminiInvoiceScanner] Gemini API timeout"
    { success: false, error: "Gemini API timeout after #{TIMEOUT}s" }
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Gemini API error: #{e.message}"
    { success: false, error: "Gemini API error: #{e.message}" }
  end

  # Build ENHANCED Gemini prompt with strict extraction rules
  def build_enhanced_gemini_prompt(raw_text)
    <<~PROMPT
      You are an expert invoice data extraction system with STRICT extraction rules.

      Your task is to extract structured data from invoice text with MAXIMUM ACCURACY.

      =====================================
      CRITICAL EXTRACTION RULES (MUST FOLLOW):
      =====================================

       1. MULTI-ITEM EXTRACTION - CRITICAL:
          - Extract ALL products/items listed on the invoice.
          - Each item must be a separate object in the 'items' array.

       2. WARRANTY EXTRACTION - PER ITEM:
          - Extract warranty information specifically for EACH item.
          - Detect ALL warranty mentions for that specific product.
          - Common patterns: "1 year product", "5 years motor", etc.
          - Canonical output: list of { "component": "name", "duration_months": X }
          - If no component specified, use "product" as default.

       3. MODEL NUMBER - PER ITEM:
          - If model number missing, use product name as model number.
          - Never return null for model number.

       4. SPECIFICATIONS (JSON):
          - Capture any unique specs like "Color", "Size", "Volts", "Processor", "RAM".
          - Store in a flat JSON object for each item.

       5. INVOICE LEVEL:
          - Extract global info: seller, purchase_date (YYYY-MM-DD), total_amount, invoice_number.

      6. PRODUCT NAME:
         - Extract the main product name
         - Include brand + model if present (e.g., "Samsung 55\" QLED TV")
         - Be specific - not just "TV" but "55 inch QLED Smart TV"

      4. BRAND:
         - Extract manufacturer brand name
         - Common brands: Samsung, LG, Sony, Whirlpool, Haier, etc.
         - If brand not explicitly mentioned → infer from product name

      5. PURCHASE DATE:
         - Extract purchase/invoice date
         - Format: YYYY-MM-DD
         - If date unclear → use invoice date

      6. SELLER:
         - Extract retailer/seller name
         - Include store name and location if available

      7. TOTAL AMOUNT:
         - Extract total paid amount (numeric only, no currency symbols)
         - Include tax if itemized

      =====================================
      OUTPUT FORMAT (STRICT JSON):
      =====================================

      {
        "seller": "Store name and location",
        "purchase_date": "YYYY-MM-DD",
        "total_amount": 1234.56,
        "invoice_number": "INV-123",
        "items": [
          {
            "product_name": "Full product name",
            "brand": "Manufacturer",
            "model_number": "Model# or product_name",
            "category": "Electronics|Appliances|Furniture|Tools|Other",
            "description": "Short description",
            "specifications": {
              "color": "Silver",
              "size": "55 inch"
            },
            "warranties": [
              {
                "component": "product",
                "duration_months": 12
              }
            ]
          }
        ]
      }

      =====================================
      EXAMPLES:
      =====================================

      Example 1 - Dynamic Multi-item:
      Input: "Samsung Fridge model RS72 and LG Washing Machine bought at Croma on Mar 2nd 2024 for 150000 total. Fridge has 1yr unit + 10yr compressor warranty. LG has 2yr warranty."
      Output: {
        "seller": "Croma",
        "purchase_date": "2024-03-02",
        "total_amount": 150000.00,
        "items": [
          {
            "product_name": "Samsung Refrigerator RS72",
            "brand": "Samsung",
            "model_number": "RS72",
            "warranties": [
              {"component": "product", "duration_months": 12},
              {"component": "compressor", "duration_months": 120}
            ]
          },
          {
            "product_name": "LG Washing Machine",
            "brand": "LG",
            "model_number": "LG Washing Machine",
            "warranties": [
              {"component": "product", "duration_months": 24}
            ]
          }
        ]
      }

      =====================================
      INVOICE TEXT TO PROCESS:
      =====================================

      #{raw_text}

      =====================================
      REMINDER - CRITICAL RULES:
      =====================================
      - warranty_details: MUST extract ALL warranties (minimum 1 if any warranty mentioned)
      - model_number: NEVER blank - use product_name if model not found
      - Output ONLY valid JSON - no explanations
      - Use null for truly missing fields (except model_number)
    PROMPT
  end

  # Parse Gemini response
  def parse_gemini_response(response_text)
    return { success: false, error: "Empty response from Gemini" } if response_text.blank?

    # Clean response - remove markdown code blocks if present
    clean_response = response_text.gsub(/```json\s*/, "").gsub(/```\s*/, "").strip

    # Parse JSON
    data = JSON.parse(clean_response) rescue nil

    # Normalize: if LLM returned an array of objects, take the first one
    data = data.first if data.is_a?(Array)

    if data.blank? || !data.is_a?(Hash)
      return { success: false, error: "AI returned invalid or empty structured data. Please try again." }
    end

    # Validate required fields
    validation_result = validate_extracted_data(data)

    # We return success: true even if validation fails here, because we want to
    # run post-processing fallbacks before giving up.
    { success: true, data: data, initial_validation_error: validation_result[:error] }
  rescue JSON::ParserError => e
    Rails.logger.error "[GeminiInvoiceScanner] JSON parse error: #{e.message}"
    Rails.logger.error "[GeminiInvoiceScanner] Raw response: #{response_text}"

    # Attempt to salvage a truncated JSON response by re-parsing a truncated, valid subset
    salvaged = attempt_json_salvage(clean_response)
    if salvaged
      Rails.logger.warn "[GeminiInvoiceScanner] Salvaged partial JSON from truncated response"
      return { success: true, data: salvaged, partial: true }
    end

    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Parse error: #{e.message}"
    { success: false, error: "Parse error: #{e.message}" }
  end

  # Attempt to recover data from a truncated JSON string by brute-force trimming
  def attempt_json_salvage(raw)
    return nil if raw.blank?

    # Strategy: trim from the end, character by character, until JSON is parseable
    trimmed = raw.dup
    100.times do
      trimmed.chop!
      break if trimmed.blank?

      begin
        # Try closing the JSON object
        return JSON.parse(trimmed + "}") if trimmed.end_with?('"') || trimmed.end_with?(",") || trimmed =~ /\w\z/
        return JSON.parse(trimmed)
      rescue JSON::ParserError
        next
      end
    end

    nil
  end

  # Validate extracted data
  def validate_extracted_data(data)
    missing_fields = []

    # Check Global info
    missing_fields << "seller" if data["seller"].blank?
    missing_fields << "purchase date" if data["purchase_date"].blank?

    # Check Items
    if data["items"].blank? || !data["items"].is_a?(Array) || data["items"].empty?
      missing_fields << "at least one product"
    else
      data["items"].each_with_index do |item, idx|
        missing_fields << "product name for item #{idx+1}" if item["product_name"].blank?
        missing_fields << "brand for item #{idx+1}" if item["brand"].blank?

        # Check warranty inside items
        if item["warranties"].blank? || !item["warranties"].is_a?(Array) || item["warranties"].empty?
          # We don't fail for missing warranties anymore, but we can log it if needed
        end
      end
    end

    if missing_fields.any?
      user_error = "We couldn't identify some important details from your invoice: #{missing_fields.join(', ')}. Please check your invoice clarity or try re-uploading."
      Rails.logger.warn "[GeminiInvoiceScanner] Validation failing: #{user_error}"
      { success: false, error: user_error }
    else
      { success: true }
    end
  end

  # Post-process and validate extracted multi-item data
  def post_process_and_validate(result, raw_text)
    data = result[:data]

    Rails.logger.info "[GeminiInvoiceScanner] Starting post-processing validation for multi-item structure"

    # Global Fallbacks
    data["purchase_date"] ||= Date.current.to_s if data["purchase_date"].blank?
    data["seller"] ||= "Unknown Seller" if data["seller"].blank?

    # Item Fallbacks
    data["items"] ||= []
    data["items"].each do |item|
      item["model_number"] ||= item["product_name"]
      item["model_number"] ||= "UNKNOWN-MODEL"
      item["category"] ||= "Other"

      # Handle warranties inside items
      item["warranties"] ||= []
      item["warranties"] = item["warranties"].map do |w|
        next w unless w.is_a?(Hash)
        {
          "component"       => (w["component"] || "product").to_s.downcase.strip,
          "duration_months" => (w["duration_months"] || 12).to_i
        }
      end.reject { |w| w["duration_months"].zero? }

      # Ensure at least one default warranty if none extracted but mentioned globally
      if item["warranties"].empty? && raw_text.match?(/warranty|guarantee/i)
        item["warranties"] = [ { "component" => "product", "duration_months" => 12 } ]
      end
    end

    # Validate final data
    validation = validate_extracted_data(data)

    result[:data] = data
    result[:post_processed] = true
    result[:validation] = validation

    # If final validation fails after all fallbacks, report as failure
    unless validation[:success]
      result[:success] = false
      result[:error] = validation[:error]
    end

    Rails.logger.info "[GeminiInvoiceScanner] Post-processing complete"
    result
  end

  # Extract warranties using regex patterns (fallback when AI fails)
  def extract_warranties_with_regex(text)
    warranties = []

    # Pattern 1: "X year(s) warranty" or "X months warranty"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s*(?:warranty|guarantee)/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      duration = unit.start_with?("y") ? value * 12 : value
      warranties << { "component" => "product", "duration_months" => duration }
    end

    # Pattern 2: "X year(s) on [component]"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s*(?:warranty|guarantee)?\s*(?:on|for)\s+(\w+)/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      component = match[2].downcase
      duration = unit.start_with?("y") ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end

    # Pattern 3: "X year(s) [component] warranty"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s+(\w+)\s*warranty/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      component = match[2].downcase
      duration = unit.start_with?("y") ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end

    # Pattern 4: "compressor warranty - X years"
    text.scan(/(\w+)\s*warranty\s*[-:]\s*(\d+)\s*(year|yr|years|month|months)/i) do |match|
      component = match[0].downcase
      value = match[1].to_i
      unit = match[2].downcase
      duration = unit.start_with?("y") ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end

    # Remove duplicates and ensure at least one warranty
    warranties = warranties.uniq { |w| [ w["component"], w["duration_months"] ] }

    # If no specific component warranties but general warranty mentioned, add product warranty
    if warranties.empty? && text.match?(/warranty|guarantee/i)
      warranties << { "component" => "product", "duration_months" => 12 }
    end

    warranties
  end

  # Update invoice with extracted data
  def update_invoice_with_extracted_data(data, raw_text)
    return unless @invoice

    update_data = {
      seller: data["seller"],
      purchase_date: parse_date(data["purchase_date"]),
      amount: data["total_amount"],
      ocr_status: :completed,
      raw_ai_data: data.to_json,
      ocr_data: data.merge(raw_text: raw_text).to_json # legacy support
    }

    # Validate purchase_date
    if update_data[:purchase_date].nil? || update_data[:purchase_date] > Date.current
      update_data[:purchase_date] = Date.current
    end

    # Update invoice
    @invoice.assign_attributes(update_data)
    @invoice.save!(validate: false)

    # Process items and warranties
    process_multi_items(data["items"]) if data["items"].present?

    # Schedule product image fetch
    schedule_product_image_fetch

    Rails.logger.info "[GeminiInvoiceScanner] Updated invoice #{@invoice.id} with multi-item data"
  end

  # Process multi-item data from AI
  def process_multi_items(items)
    @invoice.invoice_items.destroy_all

    items.each_with_index do |item_data, index|
      item = @invoice.invoice_items.create!(
        product_name: item_data["product_name"],
        brand: item_data["brand"],
        model_number: item_data["model_number"],
        category: item_data["category"],
        description: item_data["description"],
        specifications: item_data["specifications"]
      )

      # Create warranties for this item
      if item_data["warranties"].present?
        item_data["warranties"].each_with_index do |w, w_idx|
          item.warranties.create!(
            component: w["component"] || "product",
            duration_months: w["duration_months"] || 12
          )

          # --- LEGACY COMPATIBILITY ---
          # Create a record in the old product_warranties table for the first item's first warranty
          if index == 0 && w_idx == 0
            ProductWarranty.create!(
              invoice: @invoice,
              component_name: w["component"] || "product",
              warranty_months: w["duration_months"] || 12,
              expires_at: @invoice.purchase_date + (w["duration_months"] || 12).months
            ) rescue nil
          end
        end
      end
    end
  end

  # Schedule reminder jobs
  def schedule_reminder_jobs
    # ProductWarranty callbacks schedule reminder milestones as warranties are created.
  end

  # Schedule product image fetch
  def schedule_product_image_fetch
    # Product image fetching is now handled synchronously in InvoiceOcrJob
  end

  # Parse date from various formats
  def parse_date(date_str)
    return nil unless date_str.present?

    formats = [
      "%Y-%m-%d", "%d-%m-%Y", "%m-%d-%Y",
      "%d/%m/%Y", "%m/%d/%Y", "%Y/%m/%d",
      "%B %d, %Y", "%d %B %Y", "%b %d, %Y", "%d %b %Y",
      "%d %b %y", "%d-%b-%y"
    ]

    original_str = date_str.to_s.strip

    formats.each do |format|
      begin
        parsed_date = Date.strptime(original_str, format)
        return parsed_date if parsed_date.year >= 2020 && parsed_date.year <= Date.current.year + 1
      rescue ArgumentError
        next
      end
    end

    begin
      parsed_date = Date.parse(original_str)
      return parsed_date if parsed_date.year >= 2020 && parsed_date.year <= Date.current.year + 1
    rescue ArgumentError
      Rails.logger.warn "[GeminiInvoiceScanner] Failed to parse date: #{original_str}"
    end

    nil
  end
end
