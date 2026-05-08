# frozen_string_literal: true

module Invoices
  # Normalizes incoming invoice parameters from various source formats
  # (FormData, JSON API, legacy flat fields, nested items) into a single
  # canonical shape that the Create/Update services expect.
  #
  # Canonical shape:
  #   {
  #     invoice_number:, purchase_date:, seller_name:, platform_name:,
  #     total_amount:, raw_ai_data:,
  #     items: [
  #       {
  #         product_name:, brand:, model:, price:, category:, description:, specifications:,
  #         item_warranties: [
  #           { component_name:, duration_months:, warranty_text: }
  #         ]
  #       }
  #     ]
  #   }
  class PayloadNormalizer
    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @raw = @raw.deep_symbolize_keys
    end

    def call
      # Try to find extracted_data (from OCR flow)
      extracted = parse_json_if_needed(@raw[:extracted_data] || @raw[:raw_ai_data])
      extracted = extracted.deep_symbolize_keys if extracted.is_a?(Hash)

      invoice_level = extract_invoice_level(extracted)

      {
        invoice_number: @raw[:invoice_number] || invoice_level[:invoice_number],
        purchase_date: @raw[:purchase_date] || invoice_level[:purchase_date],
        seller_name: @raw[:seller_name] || @raw[:seller] || invoice_level[:seller_name] || invoice_level[:seller],
        platform_name: @raw[:platform_name] || invoice_level[:platform_name],
        total_amount: parse_decimal(@raw[:total_amount] || @raw[:amount] || invoice_level[:total_amount] || invoice_level[:amount]),
        file: @raw[:file],
        raw_ai_data: extract_raw_ai_data(extracted),
        items: normalize_items(@raw[:items] || invoice_level[:items])
      }.compact
    end

    private

    def extract_invoice_level(extracted)
      return {} unless extracted.is_a?(Hash)
      extracted[:invoice_level] || extracted[:invoiceLevel] || extracted
    end

    def extract_raw_ai_data(extracted)
      # Keep the full raw OCR data for audit/debug purposes
      extracted.is_a?(Hash) ? extracted : nil
    end

    def normalize_items(items)
      collection = coerce_collection(items)

      # If no items but legacy top-level product fields exist, synthesize one item
      if collection.empty? && (@raw[:product_name].present? || @raw[:brand].present?)
        return [ build_item_from_legacy_top_level ]
      end

      collection.filter_map { |raw| normalize_item(raw) }
    end

    def normalize_item(raw)
      return nil unless raw.is_a?(Hash)
      item = raw.deep_symbolize_keys

      {
        id: item[:id],
        product_name: item[:product_name],
        brand: item[:brand],
        model: item[:model] || item[:model_number],
        price: parse_decimal(item[:price] || item[:product_price]),
        category: item[:category],
        description: item[:description],
        specifications: parse_json_if_needed(item[:specifications]) || {},
        item_warranties: normalize_warranties(item[:item_warranties] || item[:warranties])
      }.compact
    end

    def build_item_from_legacy_top_level
      {
        product_name: @raw[:product_name],
        brand: @raw[:brand],
        model: @raw[:model_number],
        price: parse_decimal(@raw[:total_amount] || @raw[:amount]),
        category: @raw[:category],
        description: @raw[:description],
        specifications: {},
        item_warranties: normalize_warranties_from_duration
      }.compact
    end

    # Build warranty from warranty_duration field (flat form param)
    def normalize_warranties_from_duration
      duration = parse_integer(@raw[:warranty_duration] || @raw[:warranty_months])
      return [] if duration.blank? || duration <= 0

      [ {
        component_name: "main_unit",
        duration_months: duration,
        legacy_warranty_duration: true
      } ]
    end

    def normalize_warranties(warranties)
      collection = coerce_collection(warranties)
      warranties_list = collection.filter_map do |raw|
        next unless raw.is_a?(Hash)
        w = raw.deep_symbolize_keys

        component = w[:component_name] || w[:component]
        duration = parse_integer(w[:duration_months] || w[:warranty_months])

        next if component.blank? || duration.blank?

        {
          id: w[:id],
          component_name: component.to_s.downcase.strip,
          duration_months: duration
        }.compact
      end

      # Deduplicate by keeping longest duration per component
      warranties_list.group_by { |w| w[:component_name] }
                     .values
                     .map { |group| group.max_by { |w| w[:duration_months] || 0 } }
    end

    def coerce_collection(value)
      if value.is_a?(Hash)
        value.values
      elsif value.is_a?(Array)
        value
      else
        []
      end
    end

    def parse_decimal(value)
      return nil if value.blank?
      return value.to_f if value.is_a?(Numeric)

      normalized = value.to_s.strip.delete(",")
      return nil unless normalized.match?(/\A\d+(\.\d+)?\z/)
      normalized.to_f
    end

    def parse_integer(value)
      return nil if value.blank?
      return value.to_i if value.is_a?(Numeric)

      normalized = value.to_s.strip.delete(",")
      return nil unless normalized.match?(/\A\d+\z/)
      normalized.to_i
    end

    def parse_json_if_needed(value)
      return value unless value.is_a?(String)
      JSON.parse(value)
    rescue JSON::ParserError
      value
    end
  end
end
