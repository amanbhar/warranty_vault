# frozen_string_literal: true

# Service for providing default product images based on category detection
# No external API calls - uses only local image mapping
class ProductImageService
  # Product category keywords for detection
  MAPPING_RULES = {
    "smartwatch" => {
      keywords: [ "watch", "smartwatch", "smart watch", "apple", "garmin", "fitbit", "polar", "suunto", "noise", "boat", "titan", "fossil", "casio", "g-shock" ],
      image: "default_smart_watch_image"
    },
    "fan" => {
      keywords: [ "fan", "ceiling", "table", "wall", "exhaust", "pedestal", "tower" ],
      image: "default_fan_image"
    },
    "earphone" => {
      keywords: [ "headphone", "earphone", "earbud", "headset", "bluetooth", "buds", "noise", "airpods", "true-wireless" ],
      image: "default_earphone_image"
    },
    "ac" => {
      keywords: [ "ac", "air conditioner", "air-conditioner", "aircon", "split", "window", "cooling", "voltas", "daikin", "bluestar", "lg", "samsung", "whirlpool" ],
      image: "default_ac_image"
    },
    "laptop_tablet" => {
      keywords: [ "laptop", "notebook", "macbook", "ultrabook", "computer", "tablet", "ipad", "surface", "lenovo", "dell", "hp", "acer", "asus", "galaxy-tab" ],
      image: "default_laptop_tablet_image"
    },
    "mobile_phone" => {
      keywords: [ "mobile", "phone", "smartphone", "iphone", "android", "pixel", "s23", "s22", "s24", "nord", "redmi", "poco", "realme", "infinix", "moto" ],
      image: "default_mobile_phone_image"
    },
    "refrigerator" => {
      keywords: [ "refrigerator", "fridge", "freezer", "icebox", "cooler", "whirlpool", "lg", "samsung", "bosch", "kelvinator", "haier", "godrej" ],
      image: "default_refrigerator_image"
    }
  }.freeze

  attr_reader :invoice

  def initialize(invoice)
    @invoice = invoice
  end

  # Main method to get product image (no external API calls)
  def fetch_product_image
    # Check if user uploaded a product image - use it if available
    if @invoice.product_image.attached?
      # User uploaded image - store reference and skip default mapping
      image_url = "/rails/active_storage/blobs/#{@invoice.product_image.blob.id}-#{@invoice.product_image.blob.filename}"
      store_image(image_url, "user_upload")
      return image_url
    end

    # Cache check: if already has image, don't re-process
    return @invoice.product_image_url if @invoice.product_image_url.present?

    # Use local default image based on product detection
    image_key = detect_category_key

    # Store the KEY in the DB (frontend will use this to resolve local image)
    # This allows both web and mobile to use their own local assets
    image_url = "/assets/images/#{image_key}.jpeg"

    store_image(image_url, "local_default_mapping")
    image_url
  rescue => e
    Rails.logger.error "[ProductImageService] Error getting product image for invoice #{@invoice.id}: #{e.message}"
    handle_fallback
  end

  private

  # Detect product category key based on name, brand, and keywords
  def detect_category_key
    product_name = (@invoice.product_name || "").downcase
    brand = (@invoice.brand || "").downcase
    category = (@invoice.category || "").downcase
    combined_text = "#{product_name} #{brand} #{category}"

    MAPPING_RULES.each do |key, rule|
      return rule[:image] if rule[:keywords].any? { |kw| combined_text.include?(kw) }
    end

    "default_product_image" # Fallback key
  end

  # Store image URL/key in database
  def store_image(url, source)
    return if url.blank?

    # Save in invoice. We intentionally keep only the resolved image URL
    # on invoice and avoid legacy enrichment-tracking columns.
    @invoice.update_columns(
      product_image_url: url,
      updated_at: Time.current
    )

    Rails.logger.info "[ProductImageService] Successfully assigned image #{url} for Invoice #{@invoice.id}"
  end

  # Fallback to generic product image
  def handle_fallback
    fallback_url = "/assets/images/default_product_image.jpeg"
    store_image(fallback_url, "fallback_generic")
    fallback_url
  end

  class << self
    def fetch_for_invoice(invoice)
      new(invoice).fetch_product_image
    end
  end
end
