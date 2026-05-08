# frozen_string_literal: true

module Invoices
  # Dashboard aggregation query.
  #
  # Usage:
  #   data = Invoices::DashboardQuery.new(user: user).call
  class DashboardQuery
    def initialize(user:)
      @user = user
    end

    def call
      cache_key = "user:#{@user.id}:dashboard"

      CacheService.fetch(cache_key, ttl: 5.minutes) do
        invoices = @user.invoices.processed
        warranties = ItemWarranty.joins(invoice_item: :invoice).where(invoices: { user_id: @user.id, status: :processed })
        items = InvoiceItem.joins(:invoice)
          .includes(:item_warranties)
          .where(invoices: { user_id: @user.id, status: :processed })
        item_status_counts = WarrantyStatusCalculator.count_product_statuses(items)

        {
          summary: {
            total_invoices: invoices.count,
            total_value: invoices.sum(:total_amount).to_f || 0,
            active_warranties: item_status_counts[:active],
            expiring_soon: item_status_counts[:expiring],
            expired: item_status_counts[:expired]
          },
          upcoming_expirations: build_upcoming_expirations(warranties),
          recent_invoices: invoices.order(created_at: :desc).limit(5)
        }
      end
    end

    private

    def build_upcoming_expirations(warranties)
      warranties
        .where(expires_at: Date.current..7.days.from_now.to_date)
        .includes(invoice_item: :invoice)
        .order(expires_at: :asc)
        .limit(10)
        .map do |w|
          {
            id: w.id,
            component_name: w.component_name,
            component_display: w.component_display_name,
            product_name: w.invoice_item.product_name,
            brand: w.invoice_item.brand,
            expires_at: w.expires_at,
            days_remaining: w.days_remaining,
            warranty_months: w.duration_months,
            invoice_id: w.invoice_item.invoice_id
          }
        end
    end
  end
end
