# Parses extracted OCR text to identify invoice fields
class InvoiceFieldParser
  attr_reader :text

  def initialize(text)
    @text = text.to_s
  end

  # Parse all fields from OCR text
  def parse
    {
      product_name: extract_product_name,
      brand: extract_brand,
      model_number: extract_model_number,
      seller: extract_seller,
      amount: extract_amount,
      purchase_date: extract_purchase_date,
      warranty_duration_months: extract_warranty_period,
      warranty_details: extract_warranty_details,
      category: extract_category
    }
  end

  private

  # Extract product name - look for common patterns
  def extract_product_name
    # Try to find product descriptions after common keywords
    patterns = [
      /(?:product|item|description|name|description of goods)[:\s]+([^\n]+)/i,
      /^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*(?:\s+\d+[A-Z]*)?)/, # Capitalized product names
      /(?:model|description)[:\s]+([^\n]+)/i
    ]

    # Prioritize "DETAILS OF GOODS TRANSPORTED" for logic specific to logistics/retail invoices (common in India)
    if text.match?(/details\s+of\s+goods\s+transported/i)
      # Find the section, then find the first line after headers that isn't a header themselves
      # Use a more flexible regex for the header as it often spans lines
      gta_pos = text.index(/description\s+of/i)
      if gta_pos
        sub_text = text[gta_pos..-1]
        sub_lines = sub_text.split("\n").map(&:strip).reject(&:blank?)
        # Skip the header lines (usually first 2-3 lines in this section)
        start_index = sub_lines.index { |l| !l.downcase.match?(/description|goods|qty|weight|value|consignment/) }
        if start_index
          potential_lines = sub_lines[start_index..start_index+8]
          # Collect consecutive lines that look like product details
          collected = []
          potential_lines.each do |l|
            break if looks_like_table_header?(l) || looks_like_charge?(l) || looks_like_address?(l) || looks_like_price?(l)
            cleaned = clean_product_line(l)
            collected << cleaned if cleaned.present? && meaningful_line?(cleaned)
          end
          return collected.join(" ").strip if collected.any?
        end
      end
    end

    patterns.each do |pattern|
      match = text.match(pattern)
      if match
        name = match[1].strip
        if name.blank? || looks_like_table_header?(name)
          # If the immediate line is blank or just a header, look at the next few lines
          label_pos = text.index(match[0])
          sub_text = text[label_pos + match[0].length..-1]
          sub_lines = sub_text.split("\n").map(&:strip).reject(&:blank?).first(10)

          collected = []
          sub_lines.each do |l|
            break if looks_like_table_header?(l) || looks_like_charge?(l) || looks_like_address?(l)
            cleaned = clean_product_line(l)
            collected << cleaned if cleaned.present? && meaningful_line?(cleaned)
          end
          name = collected.join(" ").strip
        end

        name = clean_product_line(name)
        return name if name.present? && !looks_like_address?(name) && !looks_like_charge?(name)
      end
    end

    # More flexible multi-line match for "Description of Goods"
    if text.match?(/description\s+of\n\s*goods/i) || text.match?(/descrip.*\n.*goods/i)
      lines.each_with_index do |line, i|
        if line.downcase.include?("goods") && lines[i-1]&.downcase&.include?("description")
          # Found it! Look at the next few lines
          collected = []
          lines[i+1..i+10].each do |l|
            break if looks_like_table_header?(l) || looks_like_charge?(l) || looks_like_address?(l)
            cleaned = clean_product_line(l)
            collected << cleaned if cleaned.present? && meaningful_line?(cleaned)
          end
          return collected.join(" ").strip if collected.any?
        end
      end
    end

    # Fallback: find any line that looks like a product (High weight of uppercase or specific keywords)
    product_keywords = %w[refrigerator fridge tv washing machine laptop phone smartphone tablet watch microwave oven dryer]
    lines.each do |line|
      next unless meaningful_line?(line)
      next if looks_like_table_header?(line) || looks_like_address?(line) || looks_like_charge?(line)
      return clean_product_line(line) if product_keywords.any? { |kw| line.downcase.include?(kw) }
    end

    # Last resort fallback
    res = lines.find { |line| meaningful_line?(line) && !looks_like_date?(line) && !looks_like_price?(line) && !looks_like_table_header?(line) && !looks_like_address?(line) && !looks_like_charge?(line) }
    clean_product_line(res)
  end

  def clean_product_line(line)
    return nil if line.blank?

    # Specific cleanup for Flipkart/Logistics table rows where product name is followed by Qty, Weight, Price
    # e.g., "Samsung 236 L 1.0 53900.0 grams 19290.0"
    if line.match?(/\s+\d+(\.\d+)?\s+\d+(\.\d+)?\s+(grams|kg|ml|l|unit|qty|nos)/i)
      # Extract only the leading part that doesn't look like the start of the table data
      # Usually search for the first occurrence of a standalone number followed by another number/unit
      if match = line.match(/^(.+?)\s+\d+(\.\d+)?\s+\d+(\.\d+)?/)
        return match[1].strip
      end
    end

    cleaned = line.dup
    # Remove trailing item counts like (1)
    cleaned = cleaned.gsub(/\s*\(\d+\)\s*$/, "")

    # Remove large blocks of spaces followed by numbers (likely table columns)
    cleaned = cleaned.gsub(/\s{3,}\d+.*$/, "")

    cleaned.strip
  end

  def looks_like_charge?(str)
    keywords = %w[freight charge shipping delivery service pick up pickup handling fee tax igst cgst sgst courier postage used used\ product exchange]
    down_str = str.downcase
    # Matches if it contains any charge keyword and is relatively short or looks like a formal description
    return true if keywords.any? { |kw| down_str.include?(kw) } && down_str.split.size < 10
    false
  end

  def looks_like_table_header?(str)
    # Common table headers/titles in invoices to skip for product name
    headers = %w[qty gross amount taxable taxable_value sgst cgst igst tax discount total particulars hsn sac description invoice product_name value weight weight_of price rate unit]
    titles = [ "tax invoice", "bill of supply", "simplified invoice", "credit note", "debit note", "sold by", "ship-to", "bill-to" ]

    down_str = str.downcase.strip
    return true if titles.any? { |t| down_str.include?(t) }

    words = down_str.split
    # Catch lines that are just a few words, mostly keywords
    return true if words.any? { |w| %w[qty weight hsn sac igst cgst sgst].include?(w) }

    # If the line contains mostly these keywords, it's likely a header
    count = words.count { |w| headers.include?(w) || w.match?(/[\/%\₹\$]/) }
    count > (words.size / 3.0) # More sensitive
  end

  # Extract brand name
  def extract_brand
    known_brands = %w[
      Apple Samsung Sony LG Dell HP Lenovo Asus Acer Canon Nikon
      Bose JBL Beats Garmin Fitbit Xiaomi OnePlus Google Microsoft
      Nintendo PlayStation Xbox Amazon IKEA Target Walmart BestBuy
    ]

    known_brands.each do |brand|
      return brand if text.match?(/\b#{brand}\b/i)
    end

    # Try to find brand patterns
    patterns = [
      /(?:brand|manufacturer|made by)[:\s]+([^\n]+)/i,
      /^([A-Z]{2,})/, # All caps abbreviations
      /(?:®|™|©)\s*([^\s]+)/ # Trademark symbols
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      return match[1].strip if match
    end

    nil
  end

  # Extract model number
  def extract_model_number
    patterns = [
      /(?:model(?:\s*no\.?|\s*number|\s*#)?)[:\s]+([A-Z0-9][\w\-\/]{2,30})/i,
      /(?:part\s*no\.?|part\s*number|sku|item\s*no\.?)[:\s]+([A-Z0-9][\w\-\/]{2,30})/i,
      /(?:serial\s*(?:no\.?|number)?)[:\s]+([A-Z0-9][\w\-\/]{4,30})/i
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      return match[1].strip.upcase if match
    end

    nil
  end

  # Extract seller/store name
  def extract_seller
    patterns = [
      /(?:sold by|seller|store|shop|retailer|purchased from|bought at)[:\s]+([^\n]+)/i,
      /(?:thank you for shopping at|welcome to|visit us at)[:\s]+([^\n]+)/i,
      /^(?:AT&T|Verizon|T-Mobile|Best Buy|Target|Walmart|Amazon|Costco|Home Depot|Lowes)/i
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      return match[1].strip if match
    end

    nil
  end

  # Extract price/amount
  def extract_amount
    patterns = [
      /(?:total|amount|price|subtotal|grand total|balance)[:\s]*\$?([\d,]+\.?\d*)/i,
      /\$\s*([\d,]+\.?\d*)/,
      /([\d,]+\.?\d*)\s*(?:USD|dollars?)/i,
      /(?:Rs\.?|₹)\s*([\d,]+\.?\d*)/i
    ]

    amounts = []
    patterns.each do |pattern|
      text.scan(pattern).each do |match|
        amount = match.first.gsub(",", "").to_f
        amounts << amount if amount > 0
      end
    end

    # Return the largest amount (likely the total)
    amounts.max&.to_f
  end

  # Extract purchase date
  def extract_purchase_date
    patterns = [
      # EU/India format: 15-01-2024
      [ /(?:date|purchase date|invoice date|order date|sold on)[:\s]*(\d{1,2}-\d{1,2}-\d{2,4})/i, "%d-%m-%Y" ],
      # ISO format: 2024-01-15
      [ /(?:date|purchase date|invoice date|order date|sold on)[:\s]*(\d{4}-\d{2}-\d{2})/i, "%Y-%m-%d" ],
      # US format: 01/15/2024 or 1/15/2024
      [ /(?:date|purchase date|invoice date|order date)[:\s]*(\d{1,2}\/\d{1,2}\/\d{2,4})/i, "%m/%d/%Y" ],
      # EU format: 15/01/2024
      [ /(?:date|purchase date|invoice date|order date)[:\s]*(\d{1,2}\.\d{1,2}\.\d{2,4})/i, "%d.%m.%Y" ],
      # Written format: January 15, 2024
      [ /(?:date|purchase date|invoice date|order date)[:\s]*([A-Z][a-z]+ \d{1,2},? \d{4})/i, "%B %d, %Y" ],
      # Short written: 15 Jan 2024
      [ /(?:date|purchase date|invoice date|order date)[:\s]*(\d{1,2} [A-Z][a-z]+ \d{2,4})/i, "%d %b %Y" ]
    ]

    patterns.each do |pattern, format|
      match = text.match(pattern)
      if match
        date_str = match[1]
        begin
          return Date.strptime(date_str, format).to_s
        rescue ArgumentError
          # Try parsing with Date.parse as fallback
          begin
            return Date.parse(date_str).to_s
          rescue ArgumentError
            next
          end
        end
      end
    end

    # Fallback: find any date-like pattern
    date_patterns = [
      [ /\b(\d{4}-\d{2}-\d{2})\b/, "%Y-%m-%d" ],
      [ /\b(\d{1,2}\/\d{1,2}\/\d{2,4})\b/, "%m/%d/%Y" ],
      [ /\b(\d{1,2}\.\d{1,2}\.\d{2,4})\b/, "%d.%m.%Y" ]
    ]

    date_patterns.each do |pattern, format|
      match = text.match(pattern)
      if match
        begin
          return Date.strptime(match[1], format).to_s
        rescue ArgumentError
          next
        end
      end
    end

    nil
  end

  # Extract warranty period (in months)
  def extract_warranty_period
    patterns = [
      /(?:warranty|guarantee)[:\s]*(\d+)\s*(month|year|day)s?/i,
      /(\d+)\s*(month|year|day)\s*(?:warranty|guarantee)/i,
      /(\d+)-(?:month|year|day)\s*(?:warranty|guarantee)/i
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      if match
        value = match[1].to_i
        unit = match[2].downcase

        return case unit
               when "year" then value * 12
               when "day" then (value / 30.0).round
               else value # months
               end
      end
    end

    # Common warranty periods mentioned
    if text.match?(/\b(1|one)\s*year\s*warranty\b/i)
      return 12
    elsif text.match?(/\b(2|two)\s*year\s*warranty\b/i)
      return 24
    end

    nil
  end

  def extract_warranty_details
    patterns = [
      /warranty[^.\n]{0,200}/i,
      /guarantee[^.\n]{0,200}/i
    ]

    details = []
    patterns.each do |pattern|
      text.scan(pattern).each { |m| details << m.strip }
    end

    return [] if details.empty?

    # Return structured format compatible with scanner
    [ {
      "component" => "product",
      "duration_months" => extract_warranty_period,
      "description" => details.uniq.join(" | ")
    } ]
  end

  # Extract category based on product/brand
  def extract_category
    product = extract_product_name&.downcase || ""
    brand = extract_brand&.downcase || ""

    categories = {
      "electronics" => %w[phone laptop tablet computer camera tv headphone speaker watch],
      "appliances" => %w[refrigerator washer dryer microwave oven dishwasher vacuum],
      "furniture" => %w[chair table sofa bed desk cabinet mattress],
      "clothing" => %w[shirt pants dress jacket shoes coat],
      "tools" => %w[drill saw hammer wrench screwdriver],
      "sports" => %w[bike treadmill yoga fitness golf tennis]
    }

    text_combined = "#{product} #{brand} #{text.downcase}"

    categories.each do |category, keywords|
      return category if keywords.any? { |kw| text_combined.include?(kw) }
    end

    "general"
  end

  # Get lines from text
  def lines
    @lines ||= text.split("\n").map(&:strip).reject(&:blank?)
  end

  # Check if line is meaningful (not just numbers/symbols)
  def meaningful_line?(line)
    return false if line.blank?
    line = line.strip
    return false if line.length < 3

    # If it's strictly a date or price, it's not a product name line
    return false if looks_like_date?(line)
    return false if line.match?(/^[\d,.]+%?\s*$/) # just numbers/percent

    # Should have some letters
    line.match?(/[a-zA-Z]/) && !looks_like_address?(line) && !looks_like_charge?(line)
  end

  def looks_like_address?(str)
    # Common address keywords to skip for product name
    keywords = %w[
      behind near opposite opposite floor plot flat room sector road marg chowk
      mandir optical street avenue lane colony nagar enclave complex building
      apartment office industrial area phase stage circle square gate
      patnipura indore mumbai delhi bangalore chennai pune hyderabad kolkata
      karnataka maharashtra gujarat rajasthan tamil nadu pradesh bihar
      india pincode pin code zip phone mobile xxxxx baba verma nainshree
      authorized signatory signature flipkart amazon btpl btpl distribution
      private limited regd office contact helpcentre website tax invoice
      credit note original invoice reason of issuance page consignee consignor
      consignor details consignee details place of origin destination registration
      goods carriage vehicle transport commencement forward charge reverse
      declaration terms conditions e.& o.e e.&o.e geeta chowk
    ]

    down_str = str.downcase
    # High confidence address lines
    return true if down_str.match?(/\d+\s+[a-z]+\s+(road|street|st|ave|ave|lane|ln|ln|colony|complex)/i)
    return true if down_str.match?(/pincode[:\s]*\d{6}/i)

    # If the line contains at least a few address keywords, it's likely an address
    count = keywords.count { |kw| down_str.include?(kw) }
    count >= 2
  end

  def looks_like_date?(str)
    str.match?(/\d{4}[-\/.]\d{2}[-\/.]\d{2}/) ||
      str.match?(/\d{1,2}[-\/.]\d{1,2}[-\/.]\d{2,4}/) ||
      str.match?(/[A-Z][a-z]+ \d{1,2},? \d{4}/)
  end

  def looks_like_price?(str)
    # Only true if the line is strictly a currency/price format without much other text
    s = str.strip
    return true if s.match?(/^[₹\$\d,.]+\s*(USD|dollars?|Rs\.?|₹)?$/i)
    false
  end

  def looks_like_phone?(str)
    str.match?(/[\d\-\(\)\s\+]{10,}/)
  end

  def looks_like_url?(str)
    str.match?(/https?:\/\/|www\./i)
  end
end
