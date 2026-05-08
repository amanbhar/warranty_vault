# frozen_string_literal: true

class ItemWarrantySerializer
  # Serializes an ItemWarranty record into a JSON-friendly hash.
  #
  # Usage:
  #   ItemWarrantySerializer.render(warranty)
  #   ItemWarrantySerializer.render_collection(warranties)
  def self.render(warranty)
    {
      id: warranty.id,
      component_name: warranty.component_name,
      component_display: warranty.component_display_name,
      duration_months: warranty.duration_months,
      duration_display: warranty.duration_display,
      years: warranty.years,
      months_only: warranty.months_only,
      start_date: warranty.start_date,
      expires_at: warranty.expires_at,
      days_remaining: warranty.days_remaining,
      status: warranty.status,
      created_at: warranty.created_at,
      updated_at: warranty.updated_at
    }
  end

  def self.render_collection(warranties)
    warranties.map { |warranty| render(warranty) }
  end
end
