# Parses OCR-extracted text to identify and extract warranty information
# Handles multiple warranties per product (e.g., product + compressor + battery)
class WarrantyParserService
  attr_reader :invoice

  def initialize(invoice)
    @invoice = invoice
  end

  # Main entry point - parse OCR data and create product warranties
  def process
    return unless @invoice.ocr_data.present?

    ocr_data = @invoice.ocr_data_hash
    raw_text = ocr_data["raw_text"] || ""

    Rails.logger.info "[WarrantyParser] Starting warranty extraction for invoice #{@invoice.id}"

    # Extract warranty information from raw OCR text
    warranties = extract_warranties(raw_text)

    # Create product warranty records
    warranties.each do |warranty_data|
      create_or_update_warranty(warranty_data)
    end

    Rails.logger.info "[WarrantyParser] Created #{warranties.size} warranty records for invoice #{@invoice.id}"

    warranties
  end

  private

  # Extract warranty information from raw text
  def extract_warranties(text)
    warranties = []

    # Pattern 1: "X year(s) warranty on [component]"
    # Examples: "1 year warranty on product", "20 years on compressor"
    pattern1 = /(\d+)\s*(year|month)s?\s*(?:warranty|guarantee)?\s*(?:on|for|covering)?\s*(?:the\s*)?(\w+)?/i

    # Pattern 2: "[component] - X year(s)"
    # Examples: "Compressor - 10 years", "Product - 1 year"
    pattern2 = /(\w+)\s*[-:]\s*(\d+)\s*(year|month)s?/i

    # Pattern 3: "X year(s) [component] warranty"
    # Examples: "1 year product warranty", "5 years motor warranty"
    pattern3 = /(\d+)\s*(year|month)s?\s+(\w+)\s*warranty/i

    # Pattern 4: Standalone warranty periods
    # Examples: "1 year comprehensive", "24 months limited"
    pattern4 = /(\d+)\s*(year|month)s?\s+(comprehensive|limited|extended|standard)?/i

    # Try pattern 1
    text.scan(pattern1).each do |match|
      duration = match[0].to_i
      unit = match[1].downcase
      component = match[2]&.downcase

      next if duration.zero?

      months = unit == "year" ? duration * 12 : duration
      component = "product" if component.blank? || component == "the"

      warranties << {
        component_name: normalize_component_name(component),
        warranty_months: months,
        warranty_text: match[0]
      }
    end

    # Try pattern 2
    text.scan(pattern2).each do |match|
      component = match[0].downcase
      duration = match[1].to_i
      unit = match[2].downcase

      next if duration.zero?

      months = unit == "year" ? duration * 12 : duration

      warranties << {
        component_name: normalize_component_name(component),
        warranty_months: months,
        warranty_text: "#{duration} #{unit}(s) on #{component}"
      }
    end

    # Try pattern 3
    text.scan(pattern3).each do |match|
      duration = match[0].to_i
      unit = match[1].downcase
      component = match[2].downcase

      next if duration.zero?

      months = unit == "year" ? duration * 12 : duration

      warranties << {
        component_name: normalize_component_name(component),
        warranty_months: months,
        warranty_text: "#{duration} #{unit}(s) #{component} warranty"
      }
    end

    # If no warranties found, use default from invoice
    if warranties.empty? && @invoice.warranty_duration.present?
      warranties << {
        component_name: "product",
        warranty_months: @invoice.warranty_duration,
        warranty_text: "#{@invoice.warranty_duration} months (from invoice data)"
      }
    end

    # Deduplicate by component name (keep longest warranty)
    warranties = deduplicate_warranties(warranties)

    warranties
  end

  # Normalize component names to standard values
  def normalize_component_name(name)
    return "product" if name.blank?

    name = name.downcase.strip

    # Map common variations to standard names
    component_mapping = {
      "product" => [ "product", "products", "item", "items", "unit", "goods", " merchandise" ],
      "compressor" => [ "compressor", "compressors", "comp" ],
      "battery" => [ "battery", "batteries", "batt" ],
      "motor" => [ "motor", "motors", "engine", "engines" ],
      "panel" => [ "panel", "panels", "display panel", "control panel" ],
      "display" => [ "display", "screen", "lcd", "led", "oled" ],
      "pump" => [ "pump", "pumps", "water pump", "circulation pump" ],
      "filter" => [ "filter", "filters", "air filter", "water filter" ],
      "heating" => [ "heating", "heater", "heat exchanger" ],
      "cooling" => [ "cooling", "cooler", "coolant" ],
      "electrical" => [ "electrical", "electronics", "circuit", "wiring" ],
      "plumbing" => [ "plumbing", "pipes", "water system" ],
      "structural" => [ "structural", "structure", "frame", "chassis" ],
      "appliance" => [ "appliance", "appliances" ]
    }

    component_mapping.each do |standard, variations|
      return standard if variations.any? { |v| name.include?(v) }
    end

    # If no match, use the original name (cleaned)
    name.gsub(/[^a-z]/, "_")
  end

  # Deduplicate warranties - keep longest warranty per component
  def deduplicate_warranties(warranties)
    warranties.group_by { |w| w[:component_name] }.map do |component, items|
      items.max_by { |w| w[:warranty_months] }
    end.compact
  end

  # Create or update warranty record
  def create_or_update_warranty(warranty_data)
    return nil unless warranty_data[:warranty_months].present?

    # Calculate expiry date
    purchase_date = @invoice.purchase_date
    return nil unless purchase_date

    expires_at = purchase_date + warranty_data[:warranty_months].months

    # Find or create warranty
    warranty = @invoice.product_warranties.find_or_initialize_by(
      component_name: warranty_data[:component_name]
    )

    warranty.warranty_months = warranty_data[:warranty_months]
    warranty.expires_at = expires_at
    warranty.purchase_date = purchase_date
    warranty.warranty_text = warranty_data[:warranty_text]

    warranty.save!

    Rails.logger.info "[WarrantyParser] Created/updated warranty: #{warranty.component_name} - #{warranty.warranty_months} months"

    warranty
  rescue => e
    Rails.logger.error "[WarrantyParser] Error creating warranty: #{e.message}"
    nil
  end
end
