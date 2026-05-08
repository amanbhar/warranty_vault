# frozen_string_literal: true

# Product model for storing enriched product data
# Aggregates data from multiple sources (APIs, web scraping, AI parsing)
class Product < ApplicationRecord
  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :brand, length: { maximum: 100 }, allow_nil: true
  validates :model_number, length: { maximum: 100 }, allow_nil: true
  validates :category, inclusion: {
    in: %w[electronics appliances furniture clothing tools sports automotive general],
    allow_nil: true
  }

  # Scopes
  scope :by_brand, ->(brand) { where("LOWER(brand) = ?", brand.to_s.downcase) }
  scope :by_category, ->(category) { where(category: category) }
  scope :with_support_info, -> { where.not(support_phone: nil).or(where.not(support_email: nil)) }
  scope :recently_synced, -> { where("last_synced_at > ?", 30.days.ago) }
  scope :popular, -> { order(popularity_score: :desc) }

  # Search scope
  scope :search, ->(query) {
    return none if query.blank?

    term = "%#{query.downcase}%"
    where(
      "LOWER(name) LIKE ? OR LOWER(brand) LIKE ? OR LOWER(model_number) LIKE ? OR LOWER(search_keywords) LIKE ?",
      term, term, term, term
    )
  }

  # Callbacks
  before_save :generate_search_keywords

  # Get formatted product name with brand
  def full_name
    [ brand, name ].compact.join(" ")
  end

  # Get display name (includes model number if available)
  def display_name
    parts = [ brand, name, model_number ].compact
    parts.join(" ")
  end

  # Get primary image URL
  def primary_image
    product_image_url || images&.first&.dig("url")
  end

  # Get all product links
  def all_links
    links = []

    links << { type: "official", url: official_website } if official_website.present?
    links << { type: "amazon", url: amazon_url } if amazon_url.present?
    links << { type: "manufacturer", url: manufacturer_url } if manufacturer_url.present?

    if product_links.present?
      links += product_links.select { |l| l["url"].present? }
    end

    links.uniq { |l| l[:url] || l["url"] }
  end

  # Get support contact info as hash
  def support_contact
    {
      phone: support_phone,
      email: support_email,
      website: support_website,
      additional_info: support_info
    }.compact
  end

  # Get formatted warranty info
  def formatted_warranty
    return nil unless standard_warranty_months

    months = standard_warranty_months
    if months >= 12 && (months % 12).zero?
      years = months / 12
      "#{years} year#{'s' if years > 1}"
    else
      "#{months} month#{'s' if months > 1}"
    end
  end

  # Check if product has complete data
  def complete?
    name.present? && brand.present? && product_image_url.present? && description.present?
  end

  # Check if support info is available
  def has_support_info?
    support_phone.present? || support_email.present? || support_website.present?
  end

  # Update popularity score
  def increment_popularity!
    increment!(:popularity_score, 1)
  end

  # Mark as synced
  def mark_synced!(source: nil, metadata: {})
    update_columns(
      last_synced_at: Time.current,
      data_source: source,
      sync_metadata: metadata.to_json
    )
  end

  # Find or create product from invoice data
  def self.find_or_create_from_invoice(invoice)
    return nil unless invoice.brand.present? || invoice.product_name.present?

    # Try to find existing product
    product = find_by(
      brand: invoice.brand&.downcase,
      model_number: invoice.model_number&.upcase
    )

    if product
      product.increment_popularity!
      return product
    end

    # Create new product
    create!(
      name: invoice.product_name || "Unknown Product",
      brand: invoice.brand || "Unknown Brand",
      model_number: invoice.model_number,
      category: invoice.category,
      description: invoice.description,
      product_image_url: invoice.product_image_url
    )
  end

  # Search for product across multiple fields
  def self.smart_search(query)
    return none if query.blank?

    # Normalize query
    normalized_query = query.to_s.strip.downcase

    # Try exact model number match first
    results = where("LOWER(model_number) = ?", normalized_query)

    # If no results, try broader search
    if results.empty?
      results = search(query)
    end

    results
  end

  private

  # Generate search keywords for faster lookups
  def generate_search_keywords
    keywords = []

    # Add name variations
    keywords << name.downcase if name.present?
    keywords << brand.downcase if brand.present?
    keywords << model_number.downcase if model_number.present?

    # Add category
    keywords << category if category.present?

    # Remove duplicates and join
    self.search_keywords = keywords.uniq.compact.join(" ")
  end
end
