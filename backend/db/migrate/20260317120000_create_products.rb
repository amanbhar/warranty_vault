# frozen_string_literal: true

# Create products table for storing enriched product data
# This table stores canonical product information fetched from various APIs
class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      # Product identification
      t.string :name, null: false
      t.string :brand
      t.string :model_number
      t.string :category

      # Product details
      t.text :description
      t.string :product_image_url
      t.string :product_image_source
      t.json :images  # Multiple images [{url, source, type}]
      t.json :specifications  # Key-value specs

      # Links and references
      t.string :official_website
      t.string :amazon_url
      t.string :manufacturer_url
      t.json :product_links  # Multiple links [{type, url}]

      # Support information
      t.string :support_phone
      t.string :support_email
      t.string :support_website
      t.text :support_info  # Additional support details
      t.json :contact_info  # Structured contact data

      # Warranty information (canonical/standard warranty)
      t.integer :standard_warranty_months
      t.text :warranty_terms
      t.string :warranty_info_url

      # Source tracking
      t.string :data_source  # Which API provided this data
      t.datetime :last_synced_at
      t.json :sync_metadata

      # Caching and optimization
      t.string :search_keywords  # For faster lookups
      t.integer :popularity_score, default: 0

      t.timestamps
    end

    # Indexes for efficient lookups
    add_index :products, [ :brand, :name ]
    add_index :products, :model_number
    add_index :products, :category
    add_index :products, :search_keywords
    add_index :products, [ :brand, :model_number ], unique: true

    # Add product reference to invoices (optional - for linking)
    add_reference :invoices, :product, foreign_key: true, index: true unless column_exists?(:invoices, :product_id)
  end
end
