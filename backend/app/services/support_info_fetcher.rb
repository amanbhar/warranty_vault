# frozen_string_literal: true

# Support Information Fetcher Service
# Fetches customer support contact information for products
# Uses multiple sources: official websites, support APIs, web search
#
# Usage:
#   SupportInfoFetcher.new(brand, product_name, model_number).fetch
class SupportInfoFetcher
  class FetchError < StandardError; end

  # Timeout for HTTP requests
  HTTP_TIMEOUT = 10

  # Common support page URL patterns
  SUPPORT_PATHS = [
    "/support",
    "/contact",
    "/contact-us",
    "/customer-service",
    "/help",
    "/support/contact",
    "/support/phone",
    "/about/contact"
  ].freeze

  # Common support phone patterns in HTML
  PHONE_PATTERNS = [
    /(?:support|customer service|contact|help)[^-]*?(\+?[\d\s\-\(\)]{8,20})/i,
    /tel:([\+\d\s\-\(\)]{8,20})/i,
    /(?:call|phone|tel)[^\d]*(\+?[\d\s\-\(\)]{8,20})/i
  ].freeze

  # Common support email patterns
  EMAIL_PATTERNS = [
    /(?:support|help|service|contact)@([\w\-\.]+\.\w{2,})/i,
    /mailto:([\w\.\-\+]+@[\w\-\.]+\.\w{2,})/i
  ].freeze

  attr_reader :brand, :product_name, :model_number

  def initialize(brand, product_name, model_number = nil)
    @brand = brand&.strip
    @product_name = product_name&.strip
    @model_number = model_number&.strip
  end

  # Main entry point - fetch support information
  def fetch
    return nil if @brand.blank?

    Rails.logger.info "[SupportInfoFetcher] Fetching support info for #{@brand} #{@product_name}"

    # Step 1: Check if we have cached data
    cached = find_cached_support_info
    return cached if cached.present?

    # Step 2: Try known support databases
    info = fetch_from_support_database

    # Step 3: Search official website
    if info.blank? || info[:confidence] < 0.8
      web_info = fetch_from_official_website
      info = merge_support_info(info, web_info)
    end

    # Step 4: Use AI to extract from website if needed
    if info[:phone].blank? || info[:email].blank?
      ai_info = extract_support_with_ai
      info = merge_support_info(info, ai_info)
    end

    # Step 5: Validate and normalize
    info = normalize_support_info(info) if info.present?

    # Cache the results
    cache_support_info(info) if info.present?

    info
  rescue => e
    Rails.logger.error "[SupportInfoFetcher] Error: #{e.message}"
    Rails.logger.error "[SupportInfoFetcher] #{e.class}: #{e.backtrace.first(3).join("\n")}"
    nil
  end

  private

  # Find cached support info from Product model
  def find_cached_support_info
    product = Product.find_by(brand: @brand, model_number: @model_number)
    return nil unless product&.has_support_info?

    {
      phone: product.support_phone,
      email: product.support_email,
      website: product.support_website,
      info: product.support_info,
      contact_info: product.contact_info,
      confidence: 1.0
    }
  end

  # Fetch from support information databases
  def fetch_from_support_database
    info = {}

    # Check for brand-specific support info
    brand_support = BRAND_SUPPORT_DB[@brand&.downcase]

    if brand_support
      info = brand_support.dup
      info[:confidence] = 0.9
      info[:source] = "support_database"
    end

    info
  end

  # Fetch from official brand website
  def fetch_from_official_website
    info = {
      confidence: 0.7,
      source: "official_website"
    }

    # Find official website
    website = find_official_website

    return info if website.blank?

    info[:website] = website

    # Try to fetch support page
    SUPPORT_PATHS.each do |path|
      support_url = "#{website}#{path}"
      begin
        response = HTTParty.get(support_url, timeout: HTTP_TIMEOUT)

        if response.code == 200
          page_info = extract_contact_from_html(response.body)
          return info.merge(page_info) if page_info[:phone] || page_info[:email]
        end
      rescue => e
        Rails.logger.warn "[SupportInfoFetcher] Failed to fetch #{support_url}: #{e.message}"
        next
      end
    end

    info
  end

  # Extract support info using AI
  def extract_support_with_ai
    return {} unless ENV["OPENAI_API_KEY"].present?

    begin
      # Get website content
      website = find_official_website
      return {} if website.blank?

      support_url = "#{website}/support"
      response = HTTParty.get(support_url, timeout: HTTP_TIMEOUT)
      return {} if response.code != 200

      # Extract text content (simplified - remove HTML tags)
      text_content = response.body.gsub(/<[^>]*>/, " ").gsub(/\s+/, " ").strip

      # Send to OpenAI for extraction
      client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

      prompt = <<~PROMPT
        Extract customer support contact information from this website content:

        #{text_content[0..5000]}

        Return JSON with:
        {
          "phone": "Support phone number",
          "email": "Support email address",
          "hours": "Support hours if mentioned",
          "additional_info": "Any other support details"
        }
      PROMPT

      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            { role: "system", content: "Extract support contact information accurately." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1,
          max_tokens: 500,
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      data = JSON.parse(content)

      {
        phone: normalize_phone(data["phone"]),
        email: normalize_email(data["email"]),
        info: data["additional_info"],
        confidence: 0.8,
        source: "ai_extraction"
      }
    rescue => e
      Rails.logger.warn "[SupportInfoFetcher] AI extraction failed: #{e.message}"
      {}
    end
  end

  # Find official website for brand
  def find_official_website
    # Check product database first
    product = Product.find_by(brand: @brand)
    return product.official_website if product&.official_website.present?

    # Search for official website
    search_query = "#{@brand} official website"
    website = google_search_website(search_query)

    website
  end

  # Google search to find website
  def google_search_website(query)
    api_key = ENV.fetch("GOOGLE_API_KEY", nil)
    search_engine_id = ENV.fetch("GOOGLE_CUSTOM_SEARCH_ENGINE_ID", nil)

    return nil unless api_key && search_engine_id

    begin
      url = "https://www.googleapis.com/customsearch/v1"
      params = {
        key: api_key,
        cx: search_engine_id,
        q: query,
        num: 1
      }

      response = HTTParty.get(url, query: params, timeout: HTTP_TIMEOUT)

      if response.success?
        results = JSON.parse(response.body)
        results["items"]&.first&.dig("link")
      end
    rescue => e
      Rails.logger.warn "[SupportInfoFetcher] Google search failed: #{e.message}"
      nil
    end
  end

  # Extract contact info from HTML
  def extract_contact_from_html(html)
    info = {}

    # Extract phone numbers
    PHONE_PATTERNS.each do |pattern|
      match = html.match(pattern)
      if match
        phone = normalize_phone(match[1])
        info[:phone] = phone if phone.present?
        break
      end
    end

    # Extract email addresses
    EMAIL_PATTERNS.each do |pattern|
      match = html.match(pattern)
      if match
        email = normalize_email(match[1])
        info[:email] = email if email.present?
        break
      end
    end

    info
  end

  # Normalize phone number
  def normalize_phone(phone)
    return nil if phone.blank?

    # Remove common separators and keep only digits and +
    cleaned = phone.to_s.gsub(/[^\d+]/, "")

    # Validate minimum length
    return nil if cleaned.length < 8

    cleaned
  end

  # Normalize email
  def normalize_email(email)
    return nil if email.blank?

    # Basic email validation
    return nil unless email.match?(/[\w\.\-\+]+@[\w\-\.]+\.\w{2,}/)

    email.downcase.strip
  end

  # Merge support info from multiple sources
  def merge_support_info(existing, new)
    return new if existing.blank?
    return existing if new.blank?

    {
      phone: existing[:phone] || new[:phone],
      email: existing[:email] || new[:email],
      website: existing[:website] || new[:website],
      info: [ existing[:info], new[:info] ].compact.join(" | "),
      contact_info: (existing[:contact_info] || {}).merge(new[:contact_info] || {}),
      confidence: [ existing[:confidence], new[:confidence] ].compact.max,
      sources: [ existing[:source], new[:source] ].compact.uniq
    }.compact
  end

  # Normalize and validate support info
  def normalize_support_info(info)
    return nil if info.blank?

    {
      phone: normalize_phone(info[:phone]),
      email: normalize_email(info[:email]),
      website: info[:website]&.strip,
      info: info[:info]&.strip,
      contact_info: info[:contact_info],
      confidence: info[:confidence] || 0.5,
      source: info[:source] || "unknown",
      fetched_at: Time.current
    }.compact
  end

  # Cache support info in Product model
  def cache_support_info(info)
    Product.find_or_create_by(
      brand: @brand,
      model_number: @model_number,
      name: @product_name || "Unknown"
    ).update!(
      support_phone: info[:phone],
      support_email: info[:email],
      support_website: info[:website],
      support_info: info[:info],
      contact_info: info[:contact_info]
    )
  rescue => e
    Rails.logger.warn "[SupportInfoFetcher] Failed to cache support info: #{e.message}"
  end

  # Brand support database (common brands)
  # This is a fallback when web scraping fails
  BRAND_SUPPORT_DB = {
    "apple" => {
      phone: "1-800-275-2273",
      email: nil,
      website: "https://www.apple.com/support",
      info: "Apple Support - Available 24/7"
    },
    "samsung" => {
      phone: "1-800-726-7864",
      email: nil,
      website: "https://www.samsung.com/us/support",
      info: "Samsung Support"
    },
    "sony" => {
      phone: "1-800-222-7669",
      email: nil,
      website: "https://www.sony.com/electronics/support",
      info: "Sony Support"
    },
    "lg" => {
      phone: "1-800-243-0000",
      email: nil,
      website: "https://www.lg.com/us/support",
      info: "LG Support"
    },
    "dell" => {
      phone: "1-800-624-9896",
      email: nil,
      website: "https://www.dell.com/support",
      info: "Dell Technical Support"
    },
    "hp" => {
      phone: "1-800-334-5144",
      email: nil,
      website: "https://support.hp.com",
      info: "HP Customer Support"
    },
    "lenovo" => {
      phone: "1-855-253-6686",
      email: nil,
      website: "https://support.lenovo.com",
      info: "Lenovo Support"
    },
    "microsoft" => {
      phone: "1-800-642-7676",
      email: nil,
      website: "https://support.microsoft.com",
      info: "Microsoft Support"
    },
    "bose" => {
      phone: "1-800-999-2673",
      email: nil,
      website: "https://www.bose.com/support",
      info: "Bose Customer Service"
    },
    "canon" => {
      phone: "1-800-652-2666",
      email: nil,
      website: "https://www.usa.canon.com/support",
      info: "Canon Support"
    }
  }.freeze
end
