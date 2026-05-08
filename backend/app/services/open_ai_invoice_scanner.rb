# frozen_string_literal: true

# AI-powered Invoice Scanning Service using OpenAI
# Extracts structured product and warranty data from invoice text/images
#
# Usage:
#   OpenAiInvoiceScanner.new(invoice).process
#   OpenAiInvoiceScanner.scan_text(raw_text)
class OpenAiInvoiceScanner
  class OpenAiError < StandardError; end
  class ConfigurationError < StandardError; end

  # OpenAI model configuration from Rails config
  MODEL = Rails.application.config.ai_services.openai_model
  TEMPERATURE = Rails.application.config.ai_services.openai_temperature
  MAX_TOKENS = Rails.application.config.ai_services.openai_max_tokens

  # Timeout for API requests (seconds)
  TIMEOUT = 30

  attr_reader :invoice, :client

  def initialize(invoice)
    @invoice = invoice
    @client = build_client
  end

  # Main entry point - process invoice file with AI
  def process
    raise OpenAiError, "No file attached" unless @invoice.file.attached?

    Rails.logger.info "[OpenAiInvoiceScanner] Starting AI processing for invoice #{@invoice.id}"

    # Extract text from file (OCR first if image/PDF)
    raw_text = extract_text_from_file

    return { success: false, error: "No text extracted from file" } if raw_text.blank?

    # Send to OpenAI for structured extraction
    extract_structured_data(raw_text)
  rescue => e
    Rails.logger.error "[OpenAiInvoiceScanner] Error: #{e.message}"
    Rails.logger.error "[OpenAiInvoiceScanner] #{e.class}: #{e.backtrace.first(5).join("\n")}"
    { success: false, error: e.message }
  end

  # Class method for scanning raw text directly
  def self.scan_text(raw_text)
    scanner = new(nil)
    scanner.send(:extract_structured_data, raw_text)
  end

  # Class method for scanning with vision (image files)
  def self.scan_image(file_path, api_key: nil)
    scanner = new(nil, api_key: api_key)
    scanner.extract_from_image(file_path)
  end

  private

  # Build OpenAI client
  def build_client(api_key: nil)
    key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
    raise ConfigurationError, "OpenAI API key not configured" unless key.present?

    OpenAI::Client.new(access_token: key, request_timeout: TIMEOUT)
  end

  # Extract text from uploaded file
  def extract_text_from_file
    case @invoice.file.content_type
    when "application/pdf"
      extract_text_from_pdf
    when "image/jpeg", "image/png", "image/jpg"
      extract_text_from_image
    when "text/plain"
      @invoice.file.blob.download
    else
      # Try to read as text
      @invoice.file.blob.download
    end
  end

  # Extract text from PDF using pdf-reader gem
  def extract_text_from_pdf
    require "pdf-reader"

    file_path = download_file
    text = ""

    PDF::Reader.new(file_path).pages.each do |page|
      text += page.text + "\n"
    end

    text
  rescue LoadError
    # Fallback: try to read as binary and extract strings
    File.read(file_path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "")
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from image using Google Vision or Tesseract
  def extract_text_from_image
    # Try Google Vision first (if configured)
    if google_vision_available?
      extract_with_google_vision
    else
      # Fallback: use OpenAI Vision API
      file_path = download_file
      extract_with_openai_vision(file_path)
    end
  end

  # Extract text using Google Cloud Vision
  def extract_with_google_vision
    require "google/cloud/vision"

    file_path = download_file
    vision = Google::Cloud::Vision.new(
      project_id: ENV.fetch("GOOGLE_PROJECT_ID", nil),
      credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
    )
    file_content = File.read(file_path)
    response = vision.document_text_detection(content: file_content, mime_type: @invoice.file.content_type)
    response.full_text_annotation&.text || ""
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text using OpenAI Vision API
  def extract_with_openai_vision(file_path)
    file_content = Base64.encode64(File.read(file_path))

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Extract all text from this invoice image. Return only the raw text content."
              },
              {
                type: "image_url",
                image_url: {
                  url: "data:#{@invoice.file.content_type};base64,#{file_content}"
                }
              }
            ]
          }
        ],
        max_tokens: MAX_TOKENS
      }
    )

    response.dig("choices", 0, "message", "content") || ""
  end

  # Extract structured data using OpenAI
  def extract_structured_data(raw_text)
    Rails.logger.info "[OpenAiInvoiceScanner] Sending text to OpenAI for structured extraction"
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_messages(raw_text),
        temperature: TEMPERATURE,
        max_tokens: MAX_TOKENS,
        response_format: { type: "json_object" }
      }
    )

    # Parse result
    parsed_data = JSON.parse(content) rescue nil

    # Normalize: if LLM returned an array of objects, take the first one
    parsed_data = parsed_data.first if parsed_data.is_a?(Array)

    if parsed_data.blank? || !parsed_data.is_a?(Hash)
      return { success: false, error: "AI service returned invalid or empty data. Please try again or enter details manually." }
    end

    parsed_data = validate_and_fix(parsed_data, raw_text)

    # Normalize OpenAI's nested schema to the canonical flat schema
    flat_data = normalize_openai_response(parsed_data)

    # Update invoice with extracted data (no-op if invoice is nil)
    update_invoice_with_extracted_data(flat_data, raw_text)

    # Validate normalized data
    validation = validate_extracted_data(flat_data)

    # Validate normalized data
    validation = validate_extracted_data(flat_data)

    {
      success: validation[:success],
      data: flat_data,
      error: validation[:error],
      raw_text: raw_text
    }
  rescue JSON::ParserError => e
    Rails.logger.error "[OpenAiInvoiceScanner] Failed to parse OpenAI response: #{e.message}"
    { success: false, error: "Failed to parse AI response: #{e.message}" }
  rescue Faraday::TooManyRequestsError, StandardError => e
    if e.message.include?("429") || e.message.include?("Too Many Requests") || e.message.include?("Rate limit")
      Rails.logger.warn "[OpenAiInvoiceScanner] Rate limited by OpenAI (429). Backing off."
      { success: false, error: "OpenAI rate limit reached. Please try again in a moment." }
    else
      Rails.logger.error "[OpenAiInvoiceScanner] OpenAI error: #{e.message}"
      { success: false, error: "AI service error: #{e.message}" }
    end
  end

  # Normalize the nested OpenAI response schema into the canonical flat schema
  # that the rest of the system (frontend + InvoiceCreateService) expects.
  #
  #  OpenAI schema:  { invoice_number, seller, purchase_date, items: [{ product_name, brand, model_number, price, warranties: [] }] }
  #  Canonical:      { product_name, brand, model_number, seller, purchase_date, total_amount, invoice_number, warranty_details: [{ component, duration_months }] }
  def normalize_openai_response(data)
    return data if data.nil?

    items = (data["items"] || []).map do |item|
      {
        "product_name"    => item["product_name"] || item["name"],
        "brand"           => item["brand"],
        "model_number"    => item["model_number"] || item["product_name"],
        "category"        => item["category"],
        "description"     => item["description"],
        "specifications"  => item["specifications"] || {},
        "warranties"      => (item["warranties"] || []).map { |w|
          {
            "component"       => w["component"] || "product",
            "duration_months" => (w["duration_months"] || (w["duration_years"].to_i * 12)).to_i
          }
        }.reject { |w| w["duration_months"].to_i.zero? }
      }
    end

    {
      "seller"          => data["seller"] || data["store_name"],
      "purchase_date"   => data["purchase_date"] || data["invoice_date"],
      "total_amount"    => (data["total_amount"] || data["amount"])&.to_f,
      "invoice_number"  => data["invoice_number"],
      "items"           => items
    }
  end

  # Build messages for OpenAI API
  def build_messages(raw_text)
    [
      {
        role: "system",
        content: SYSTEM_PROMPT
      },
      {
        role: "user",
        content: "Extract structured data from the following invoice text:\n\n#{raw_text}"
      }
    ]
  end

  # Update invoice record with extracted data
  def update_invoice_with_extracted_data(data, raw_text)
    return unless @invoice

    update_data = {
      seller: data["seller"],
      amount: data["total_amount"],
      purchase_date: parse_date(data["purchase_date"]),
      ocr_data: data.merge(raw_text: raw_text).to_json,
      raw_ai_data: data.to_json,
      ocr_status: :completed
    }

    # Update invoice
    @invoice.assign_attributes(update_data)
    @invoice.save!(validate: false)

    # Process multi-items
    if data["items"].present?
      @invoice.invoice_items.destroy_all

      data["items"].each_with_index do |item_data, idx|
        item = @invoice.invoice_items.create!(
          product_name: item_data["product_name"],
          brand: item_data["brand"],
          model_number: item_data["model_number"],
          category: item_data["category"],
          description: item_data["description"],
          specifications: item_data["specifications"]
        )

        next unless item_data["warranties"].present?

        item_data["warranties"].each_with_index do |w, w_idx|
          item.warranties.create!(
            component: w["component"] || "product",
            duration_months: w["duration_months"] || 12
          )

          # --- LEGACY COMPATIBILITY ---
          if idx == 0 && w_idx == 0
            ProductWarranty.create!(
              invoice: @invoice,
              component_name: w["component"] || "product",
              warranty_months: w["duration_months"] || 12,
              expires_at: (@invoice.purchase_date || Date.current) + (w["duration_months"] || 12).months
            ) rescue nil
          end
        end
      end
    end

    # Schedule product image fetch
    schedule_product_image_fetch

    Rails.logger.info "[OpenAiInvoiceScanner] Multi-item invoice #{@invoice.id} updated"
  end

  # Schedule product image fetch job
  def schedule_product_image_fetch
    return unless @invoice.persisted?

    # Schedule image fetch to run after OCR completion
    # Product image fetching is now handled synchronously in InvoiceOcrJob
    Rails.logger.info "[OpenAiInvoiceScanner] Scheduled product image fetch for invoice #{@invoice.id}"
  end

  # Create comprehensive warranty records from extracted data
  def create_comprehensive_warranties(data)
    purchase_date = @invoice.purchase_date
    return unless purchase_date

    warranty_details = data["warranty_details"]
    return if warranty_details.blank?

    # Clear existing warranties for this invoice
    @invoice.product_warranties.destroy_all

    warranty_details.each_with_index do |warranty, index|
      # Calculate duration in months
      duration_months = warranty["duration_months"] || (warranty["duration_years"] * 12)

      # Calculate expiry date
      expiry_date = purchase_date + duration_months.months

      # Create warranty record
      ProductWarranty.create!(
        invoice: @invoice,
        component: warranty["component"],
        duration_months: duration_months,
        expires_at: expiry_date,
        description: warranty["description"],
        warranty_type: warranty["component"] == "product" ? "standard" : "extended"
      )

      Rails.logger.info "[OpenAiInvoiceScanner] Created #{warranty['component']} warranty: #{duration_months} months, expires #{expiry_date}"
    end
  end

  # Calculate total warranty duration from all warranties
  def calculate_total_warranty_duration(warranty_details)
    return nil unless warranty_details.present?

    # Find the longest warranty (usually the product warranty)
    product_warranty = warranty_details.find { |w| w["component"] == "product" }
    return nil unless product_warranty

    product_warranty["duration_months"] || (product_warranty["duration_years"] * 12)
  end

  # Store additional information
  def store_additional_info(additional_info)
    # Store in metadata or additional fields as needed
    metadata = {
      delivery_details: additional_info["delivery_details"],
      installation_details: additional_info["installation_details"],
      customer_service: additional_info["customer_service"],
      terms: additional_info["terms"]
    }.compact

    if metadata.any?
      @invoice.update_column(:metadata, metadata.to_json)
      Rails.logger.info "[OpenAiInvoiceScanner] Stored additional info: #{metadata.keys.join(', ')}"
    end
  end

  # Normalize component name to standard values
  def normalize_component(name)
    return "product" if name.blank?

    name = name.downcase.strip

    # Map common variations
    component_mapping = {
      "product" => %w[product products item unit main],
      "compressor" => %w[compressor compressors comp],
      "battery" => %w[battery batteries batt],
      "motor" => %w[motor motors engine engines],
      "display" => %w[display screen panel lcd led oled],
      "pump" => %w[pump pumps water pump circulation],
      "filter" => %w[filter filters air filter water]
    }

    component_mapping.each do |standard, variations|
      return standard if variations.any? { |v| name.include?(v) }
    end

    name.gsub(/[^a-z]/, "_")
  end

  # Parse date from various formats
  def parse_date(date_str)
    return nil unless date_str.present?

    # Try common formats
    formats = [ "%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%B %d, %Y", "%d %B %Y", "%b %d, %Y" ]

    formats.each do |format|
      begin
        return Date.strptime(date_str.to_s, format)
      rescue ArgumentError
        next
      end
    end

    # Fallback to Date.parse
    Date.parse(date_str.to_s) rescue nil
  end

  # Validate extracted data
  def validate_extracted_data(data)
    missing_fields = []

    # Check warranty_details
    if data["warranty_details"].blank? || !data["warranty_details"].is_a?(Array) || data["warranty_details"].empty?
      missing_fields << "warranty information"
    end

    # Check model_number
    if data["model_number"].blank?
      missing_fields << "model number"
    end

    # Check product_name
    if data["product_name"].blank?
      missing_fields << "product identification"
    end

    if missing_fields.any?
      user_error = "We couldn't identify some important details from your invoice: #{missing_fields.join(', ')}. Please check your invoice to ensure these details are clearly visible, or try re-uploading a clearer photo."
      Rails.logger.warn "[OpenAiInvoiceScanner] Validation failing with user-friendly message: #{user_error}"
      { success: false, error: user_error }
    else
      { success: true }
    end
  end

  # Download file to temp location
  def download_file
    file = Tempfile.new([ "invoice_", ".#{@invoice.file.filename.extension}" ])
    file.binmode
    file.write(@invoice.file.blob.download)
    file.close
    file.path
  end

  # Check if Google Vision is available
  def google_vision_available?
    ENV["GOOGLE_PROJECT_ID"].present? && ENV["GOOGLE_APPLICATION_CREDENTIALS"].present?
  end

  def validate_extracted_data(data)
    missing = []
    missing << "seller" if data["seller"].blank?
    missing << "purchase date" if data["purchase_date"].blank?

    if data["items"].blank? || !data["items"].is_a?(Array) || data["items"].empty?
      missing << "item details"
    end

    if missing.any?
      { success: false, error: "Missing required details: #{missing.join(', ')}" }
    else
      { success: true }
    end
  end

  def validate_and_fix(data, raw_text)
    # Ensure product exists
    return nil if data["items"].blank?

    data["items"].each do |item|
      # fallback for model
      item["model_number"] ||= item["product_name"]

      # fallback for brand (basic extraction)
      if item["brand"].blank?
        item["brand"] = raw_text[/Samsung|LG|Sony|Apple|Dell/i]
      end
    end

    # fallback purchase date
    if data["purchase_date"].blank?
      data["purchase_date"] = raw_text[/\d{2}\/\d{2}\/\d{4}/]
    end

    data
  end

  # System prompt for OpenAI - defines the extraction schema
  SYSTEM_PROMPT = <<~PROMPT
    You are a highly accurate invoice extraction system.

    Your task is to extract ONLY verifiable data from the invoice.

    STRICT RULES:

    1. DO NOT GUESS.
    2. DO NOT HALLUCINATE.
    3. If data is unclear → return null.
    4. Extract EXACT values only from text.

    --------------------------------

    EXTRACT:

    - product_name (required)
    - brand
    - model_number
    - seller/store name
    - invoice_number
    - purchase_date
    - item price
    - total amount
    - ALL warranties (including multiple components)

    --------------------------------

    WARRANTY RULES:

    - Convert all warranties to months
    - Extract ALL warranty types separately
    - Examples:
      "1 year product + 10 years compressor"

    Return:

    [
      { component: "product", duration_months: 12 },
      { component: "compressor", duration_months: 120 }
    ]

    --------------------------------

    MULTI-ITEM RULE:

    If multiple products exist:

    Return ALL items separately.

    --------------------------------

    CONFIDENCE RULE:

    - Only include confidence_score if sure
    - If unsure → reduce score

    --------------------------------

    OUTPUT STRICT JSON:

    {
      "invoice_number": "",
      "seller": "",
      "purchase_date": "",
      "total_amount": null,
      "items": [
        {
          "product_name": "",
          "brand": "",
          "model_number": "",
          "category": "",
          "specifications": {},
          "warranties": [
            { "component": "product", "duration_months": 12 }
          ]
        }
      ]
    }

    --------------------------------

    IMPORTANT:

    Return ONLY JSON.
    No explanation.
    No guessing.
    Missing data = null.
  PROMPT
end
