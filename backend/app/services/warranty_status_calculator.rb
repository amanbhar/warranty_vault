# frozen_string_literal: true

class WarrantyStatusCalculator
  EXPIRING_THRESHOLD_DAYS = 30

  class << self
    # Computes status for a single warranty expiry date.
    # Returns one of: "active", "expiring", "expired"
    def warranty_status(expires_at, threshold_days: EXPIRING_THRESHOLD_DAYS)
      return "expired" if expires_at.blank?

      expiry_date = expires_at.to_date
      today = Date.current
      threshold_date = threshold_days.days.from_now.to_date

      return "expired" if expiry_date < today
      return "expiring" if expiry_date <= threshold_date

      "active"
    end

    # Computes product status from all warranties.
    # Priority: active > expiring > expired
    # If no warranties are present, defaults to expired.
    def product_status(warranties, threshold_days: EXPIRING_THRESHOLD_DAYS, empty_status: "expired")
      list = Array(warranties).compact
      return empty_status if list.empty?

      statuses = list.map do |warranty|
        expiry = warranty.respond_to?(:expires_at) ? warranty.expires_at : warranty
        warranty_status(expiry, threshold_days: threshold_days)
      end

      return "active" if statuses.include?("active")
      return "expiring" if statuses.include?("expiring")

      "expired"
    end

    # Computes invoice-level status from all item statuses.
    # Priority: active > expiring > expired
    def invoice_status(items, empty_status: "expired")
      statuses = Array(items).compact.map do |item|
        item.respond_to?(:status) ? item.status : product_status(item)
      end
      return empty_status if statuses.empty?

      return "active" if statuses.include?("active")
      return "expiring" if statuses.include?("expiring")

      "expired"
    end

    def count_product_statuses(items, threshold_days: EXPIRING_THRESHOLD_DAYS)
      counts = { active: 0, expiring: 0, expired: 0 }

      Array(items).compact.each do |item|
        status =
          if item.respond_to?(:item_warranties)
            product_status(item.item_warranties, threshold_days: threshold_days)
          else
            product_status(item, threshold_days: threshold_days)
          end

        counts[status.to_sym] += 1
      end

      counts
    end
  end
end
