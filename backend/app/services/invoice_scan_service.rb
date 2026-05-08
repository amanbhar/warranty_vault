# frozen_string_literal: true

# Invoice Scan Service - Strict JSON-only extraction for scan-then-confirm flow
#
# Purpose:
# - Extract data from invoice WITHOUT creating any database records
# - Returns structured JSON for frontend display
# - Validates required fields before showing form
# - NO side effects - pure extraction service
#
# Usage:
#   result = InvoiceScanService.scan_file(file)
#   if result[:success]
#     # Show data in form for user confirmation
#   else
#     # Show error modal
#   end
class InvoiceScanService
  class ScanError < StandardError; end
  class InvalidFileError < StandardError; end
  class ExtractionError < StandardError; end

  # Required fields that MUST be present for valid scan
  # These are the minimum fields needed to create an invoice
  REQUIRED_FIELDS = %w[product_name brand seller purchase_date].freeze

  # Field mappings from AI response to our schema
  # Maps AI field names to our internal field names
  FIELD_MAPPINGS = {
    product_name: :product_name,
    brand: :brand,
    model: :model_number,
    model_number: :model_number,
    seller: :seller,
    seller_name: :seller,
    purchase_date: :purchase_date,
    warranty_period: :warranty_duration,
    amount: :amount,
    total_amount: :amount,
    price: :amount,
    product_price: :amount,
    category: :category,
    product_category: :category,
    description: :description,
    invoice_number: :invoice_number,
    currency: :currency,
    platform_name: :platform_name
  }.freeze

  attr_reader :file

  def initialize(file)
    @file = file
  end

  # Main scanning method - returns extracted data without DB writes
  def scan
    Rails.logger.info "[InvoiceScanService] Starting scan for file: #{file.original_filename}"
    # Validate file
    validate_file!

    # Extract text from file
    raw_text = extract_text_from_file

    return {
      success: false,
      error: {
        code: "NO_TEXT_EXTRACTED",
        message: "No text could be extracted from the file",
        user_message: "Could not read text from your invoice",
        suggestion: "Please ensure the file is clear and not corrupted",
        allow_manual_entry: true
      }
    } if raw_text.blank?

    Rails.logger.info "[InvoiceScanService] Extracted #{raw_text.length} characters"

    # Extract structured data with AI
    result = extract_structured_data(raw_text)

    return result unless result[:success]

    # Validate required fields
    validation = validate_required_fields(result[:data])
    unless validation[:success]
      return {
        success: false,
        error: {
          code: "INCOMPLETE_DATA",
          message: validation[:error],
          user_message: "Incomplete invoice data",
          suggestion: "Please upload a clearer invoice or enter details manually",
          missing_fields: validation[:missing_fields],
          allow_manual_entry: true
        }
      }
    end

    normalized_data = build_normalized_payload(result[:data])

    Rails.logger.info "[InvoiceScanService] Scan successful - extracted #{normalized_data[:items].first&.compact&.count || 0} item fields, #{normalized_data.dig(:items, 0, :warranties)&.count || 0} warranties"

    {
      success: true,
      message: "Invoice scanned successfully",
      data: normalized_data,
      raw_ocr_text: raw_text,
      warnings: normalized_data[:warnings] || [],
      missing_fields: normalized_data[:missing_fields] || [],
      confidence_score: calculate_confidence(normalized_data),
      scan_duration_ms: result[:scan_duration_ms],
      warning: normalized_data[:warnings]&.first
    }
  rescue InvalidFileError => e
    Rails.logger.error "[InvoiceScanService] Invalid file: #{e.message}"
    {
      success: false,
      error: {
        code: "INVALID_FILE",
        message: e.message,
        user_message: "Invalid file format",
        suggestion: "Please upload a PDF, PNG, JPG, or JPEG file",
        accepted_formats: [ "PDF", "PNG", "JPG", "JPEG" ],
        allow_manual_entry: true
      }
    }
  rescue ExtractionError => e
    Rails.logger.error "[InvoiceScanService] Extraction error: #{e.message}"
    {
      success: false,
      error: {
        code: "EXTRACTION_FAILED",
        message: e.message,
        user_message: "Failed to extract data from invoice",
        suggestion: "Please try again or enter details manually",
        allow_manual_entry: true,
        retry_allowed: true
      }
    }
  rescue => e
    Rails.logger.error "[InvoiceScanService] Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: {
        code: "UNEXPECTED_ERROR",
        message: e.message,
        user_message: "Something went wrong during scanning",
        suggestion: "Please try again or enter details manually",
        allow_manual_entry: true,
        retry_allowed: true
      }
    }
  end

  # Class method for convenience
  def self.scan_file(file)
    new(file).scan
  end

  # Class method for stateless processing (used by scan_upload endpoint)
  def self.process_file_stateless(file)
    new(file).scan
  end

  private

  # Validate file type and size
  def validate_file!
    raise InvalidFileError, "No file provided" unless file.present?

    # Check file type
    valid_types = [ "application/pdf", "image/png", "image/jpeg", "image/jpg" ]
    content_type = file.content_type.to_s.downcase

    unless valid_types.include?(content_type) || content_type.include?("pdf") || content_type.include?("image")
      raise InvalidFileError, "Invalid file type: #{content_type}"
    end

    # Check file size (max 10MB)
    if file.size > 10.megabytes
      raise InvalidFileError, "File too large: #{(file.size / 1.megabyte).round(2)}MB (max 10MB)"
    end
  end

  # Extract text from file (PDF or image)
  def extract_text_from_file
    if file.content_type&.include?("pdf")
      extract_text_from_pdf
    elsif file.content_type&.include?("image")
      extract_text_from_image
    else
      extract_text_from_document
    end
  end

  def extract_text_from_pdf
    require "pdf/reader"

    file_path = download_file
    reader = PDF::Reader.new(file_path)
    text = reader.pages.map(&:text).join("\n")
    text.strip
  rescue LoadError
    # Fallback: read raw text
    file_path = download_file
    File.read(file_path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "")
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

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

  def extract_text_from_document
    file_path = download_file
    File.read(file_path, encoding: "UTF-8").strip
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  def download_file
    file_path = Rails.root.join("tmp", "scan_#{SecureRandom.uuid}_#{file.original_filename}")
    File.open(file_path, "wb") { |f| f.write(file_bytes) }
    file_path
  end

  def file_bytes
    return file.download if file.respond_to?(:download)

    if file.respond_to?(:tempfile) && file.tempfile
      uploaded_io = file.tempfile
      uploaded_io.rewind if uploaded_io.respond_to?(:rewind)
      return uploaded_io.read
    end

    if file.respond_to?(:read)
      file.rewind if file.respond_to?(:rewind)
      return file.read
    end

    raise ExtractionError, "Unsupported uploaded file object: #{file.class.name}"
  end

  # Extract structured data using AI
  def extract_structured_data(raw_text)
    start_time = Time.current

    # Use Gemini service with strict JSON prompt
    scanner = GeminiInvoiceScannerForScan.new(raw_text)
    result = scanner.process

    scan_duration = ((Time.current - start_time) * 1000).to_i

    if result[:success]
      {
        success: true,
        data: result[:data],
        scan_duration_ms: scan_duration
      }
    else
      {
        success: false,
        error: result[:error] || "AI extraction failed",
        scan_duration_ms: scan_duration
      }
    end
  rescue => e
    Rails.logger.error "[InvoiceScanService] AI extraction error: #{e.message}"
    {
      success: false,
      error: "AI service error: #{e.message}"
    }
  end

  # Validate required fields are present
  def validate_required_fields(data)
    return { success: false, error: "No data extracted", missing_fields: REQUIRED_FIELDS } unless data.is_a?(Hash)

    first_item = first_item_from(data)
    reported_missing = Array(data["missing_fields"] || data[:missing_fields]).map(&:to_s)
    field_values = {
      "seller" => data["seller"] || data[:seller] || data["seller_name"] || data[:seller_name],
      "purchase_date" => data["purchase_date"] || data[:purchase_date],
      "product_name" => first_item["product_name"] || first_item[:product_name] || data["product_name"] || data[:product_name],
      "brand" => first_item["brand"] || first_item[:brand] || data["brand"] || data[:brand]
    }

    missing_fields = REQUIRED_FIELDS.select do |field|
      value = field_values[field]
      value.blank? || (value.is_a?(String) && value.strip.empty?) || reported_missing.include?(field)
    end

    if missing_fields.any?
      {
        success: false,
        error: "Missing required fields: #{missing_fields.join(', ')}",
        missing_fields: missing_fields
      }
    else
      { success: true }
    end
  end

  # Map AI response fields to our schema
  def map_fields(data)
    mapped = {}

    FIELD_MAPPINGS.each do |ai_field, our_field|
      value = data[ai_field.to_s] || data[ai_field.to_sym]
      mapped[our_field] = value if value.present?
    end

    if mapped[:seller].blank?
      mapped[:seller] = data.dig("invoice", "seller") || data.dig(:invoice, :seller)
    end

    if mapped[:invoice_number].blank?
      mapped[:invoice_number] = data.dig("invoice", "invoice_number") || data.dig(:invoice, :invoice_number)
    end

    # Normalize date format to ISO (YYYY-MM-DD)
    if mapped[:purchase_date].present?
      begin
        mapped[:purchase_date] = Date.parse(mapped[:purchase_date].to_s).strftime("%Y-%m-%d")
      rescue
        mapped.delete(:purchase_date)
      end
    end

    # Normalize amount to float with 2 decimal places
    if mapped[:amount].present?
      mapped[:amount] = mapped[:amount].to_f.round(2)
    end

    # Preserve structured warranties for downstream normalization.
    mapped[:warranties] = extract_warranties(data)

    # Set default category if not provided
    mapped[:category] ||= "Other"

    mapped
  end

  def build_normalized_payload(data)
    mapped = map_fields(data)
    items = normalize_items(data, mapped)
    warnings = Array(data["warnings"] || data[:warnings]).filter_map { |warning| warning.to_s.strip.presence }
    missing_fields = Array(data["missing_fields"] || data[:missing_fields]).map(&:to_s)

    # Track missing optional fields for user notification
    missing_optional_fields = []

    # Check for missing price/amount
    if items.all? { |item| item[:price].blank? } && mapped[:amount].blank?
      missing_optional_fields << "price"
      warnings << "Price information was not detected. Please manually add the price to complete your warranty record."
    end

    # Check for missing warranty details
    if items.all? { |item| item[:warranties].blank? }
      missing_optional_fields << "warranty"
      warnings << "Warranty details were not detected. Please review the invoice and manually add warranty information (duration, covered components) to ensure your products are properly covered."
    end

    # Check for missing model number
    if items.all? { |item| item[:model_number].blank? } && mapped[:model_number].blank?
      missing_optional_fields << "model_number"
      warnings << "Model number was not detected. Adding it will help identify your product more accurately."
    end

    primary_item = items.first || {}
    primary_warranties = primary_item[:warranties].presence || mapped[:warranties]

    {
      seller: mapped[:seller],
      seller_name: mapped[:seller],
      platform_name: mapped[:platform_name],
      purchase_date: mapped[:purchase_date],
      amount: mapped[:amount],
      total_amount: mapped[:amount],
      product_price: primary_item[:price] || mapped[:amount],
      invoice_number: mapped[:invoice_number],
      currency: mapped[:currency],
      category: primary_item[:category] || mapped[:category] || "Other",
      product_category: primary_item[:category] || mapped[:category] || "Other",
      product_name: primary_item[:product_name] || mapped[:product_name],
      brand: primary_item[:brand] || mapped[:brand],
      model: primary_item[:model_number] || mapped[:model_number],
      model_number: primary_item[:model_number] || mapped[:model_number],
      warranty_duration: primary_warranties&.first&.dig(:duration_months),
      items: items,
      warranties: primary_warranties,
      warnings: warnings.uniq,
      missing_fields: missing_fields.uniq,
      missing_optional_fields: missing_optional_fields.uniq
    }.compact
  end

  def normalize_items(data, mapped)
    items_data = data["items"] || data[:items]
    items = if items_data.is_a?(Array)
              items_data.filter_map do |item|
                next unless item.is_a?(Hash)

                item = item.deep_symbolize_keys
                item_warranties = extract_warranties(item)
                item_warranties = mapped[:warranties] if item_warranties.blank?
                {
                  product_name: item[:product_name],
                  brand: item[:brand],
                  model_number: item[:model_number],
                  model: item[:model] || item[:model_number],
                  category: item[:category] || mapped[:category] || "Other",
                  description: item[:description],
                  price: item[:price].presence&.to_f || item[:product_price].presence&.to_f,
                  warranties: item_warranties
                }.compact
              end
    else
              []
    end

    return items if items.any?

    [
      {
        product_name: mapped[:product_name],
        brand: mapped[:brand],
        model_number: mapped[:model_number],
        model: mapped[:model_number],
        category: mapped[:category],
        description: mapped[:description],
        warranties: mapped[:warranties]
      }.compact
    ].reject { |item| item.except(:warranties).empty? }
  end

  # Extract warranties array from AI response
  def extract_warranties(data)
    warranties_data = if data.is_a?(Hash)
      data["warranties"] || data[:warranties] || data["warranty_details"] || data[:warranty_details] ||
        data["warrantyDetails"] || data[:warrantyDetails]
    else
      data
    end
    warranties_data = warranties_data.values if warranties_data.is_a?(Hash)
    return [] unless warranties_data.is_a?(Array)

    warranties_data.filter_map do |w|
      case w
      when Hash
        parse_warranty_hash(w)
      when String
        parse_warranty_text(w)
      else
        nil
      end
    end
  end

  def parse_warranty_hash(raw_warranty)
    w = raw_warranty.deep_symbolize_keys
    details = w[:details] || w[:source_text] || w[:description]
    component = w[:component_name] || w[:component]
    component = infer_warranty_component(details) if component.blank? && details.present?
    duration_months = normalize_warranty_duration(
      w[:warranty_months] || w[:duration_months] || w[:duration] || w[:period],
      details
    )

    return nil if component.blank? && details.blank?

    {
      component: component.to_s.downcase.strip.presence || "product",
      component_name: component.to_s.downcase.strip.presence || "product",
      duration_months: duration_months,
      warranty_months: duration_months,
      warranty_type: w[:warranty_type],
      details: details
    }.tap do |warranty|
      if warranty[:duration_months].to_i <= 0
        warranty.delete(:duration_months)
        warranty.delete(:warranty_months)
      end
      warranty.delete(:warranty_type) if warranty[:warranty_type].blank?
      warranty.delete(:details) if warranty[:details].blank?
    end
  end

  def parse_warranty_text(text)
    details = text.to_s.strip
    return nil if details.blank?

    component = infer_warranty_component(details)
    duration_months = normalize_warranty_duration(nil, details)

    {
      component: component,
      component_name: component,
      duration_months: duration_months,
      warranty_months: duration_months,
      details: details
    }.tap do |warranty|
      if warranty[:duration_months].to_i <= 0
        warranty.delete(:duration_months)
        warranty.delete(:warranty_months)
      end
    end
  end

  def infer_warranty_component(details)
    text = details.to_s.downcase
    return "compressor" if text.match?(/compressor/)
    return "panel"      if text.match?(/panel/)
    return "motor"      if text.match?(/motor/)
    return "battery"    if text.match?(/batter/)
    return "screen"     if text.match?(/screen|display/)
    return "parts"      if text.match?(/parts|spare/)
    return "labour"     if text.match?(/labour|labor|service/)
    return "accessories" if text.match?(/accessor/)
    return "handset"    if text.match?(/handset/)

    "product"
  end

  def normalize_warranty_duration(explicit_duration, details)
    return explicit_duration.to_i if explicit_duration.present?

    text = details.to_s.downcase
    match = text.match(/(\d+)\s*(year|years|yr|yrs|month|months|mo|mos)\b/)
    return nil unless match

    value = match[1].to_i
    unit = match[2]
    unit.start_with?("year", "yr") ? value * 12 : value
  end

  def first_item_from(data)
    items = data["items"] || data[:items]
    return items.first if items.is_a?(Array) && items.first.is_a?(Hash)

    {}
  end

  # Calculate confidence score based on data completeness
  def calculate_confidence(data)
    total_fields = 5
    first_item = data[:items]&.first || {}
    filled_fields = [
      data[:seller],
      data[:purchase_date],
      data[:amount],
      first_item[:product_name],
      first_item[:brand]
    ].compact.count

    (filled_fields.to_f / total_fields * 100).round(2)
  end
end
