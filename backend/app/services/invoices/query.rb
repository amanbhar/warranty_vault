# frozen_string_literal: true

module Invoices
  # Query object for filtering and searching invoices.
  #
  # Usage:
  #   invoices = Invoices::Query.new(scope: user.invoices, params: { q: "Amazon", status: "active" }).call
  class Query
    def initialize(scope:, params:)
      @scope = scope
      @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.with_indifferent_access : params.to_h.with_indifferent_access
    end

    def call
      query = @scope
        .includes(invoice_items: :item_warranties)
        .where(status: [ :processed, :draft ])
        .order(created_at: :desc)

      query = by_search(query)
      query = by_status(query)
      query = by_category(query)
      query = by_seller(query)
      query = by_purchase_date(query)
      query
    end

    private

    def by_search(query)
      return query if @params[:q].blank?
      term = "%#{@params[:q]}%"
      matching_ids = query
        .left_joins(:invoice_items)
        .where(
          "invoices.seller_name ILIKE :term OR " \
          "invoices.invoice_number ILIKE :term OR " \
          "invoice_items.product_name ILIKE :term OR " \
          "invoice_items.brand ILIKE :term OR " \
          "invoice_items.category ILIKE :term",
          term: term
        )
        .unscope(:order)
        .select(:id)
        .distinct

      query.where(id: matching_ids)
    end

    def by_status(query)
      return query if @params[:status].blank?
      target_status = normalize_status(@params[:status])
      return query unless target_status

      matching_invoice_ids = query.select do |invoice|
        invoice.invoice_items.any? { |item| item.status == target_status }
      end.map(&:id)

      query.where(id: matching_invoice_ids)
    end

    def normalize_status(value)
      case value.to_s
      when "active"
        "active"
      when "expiring", "expiring_soon"
        "expiring"
      when "expired"
        "expired"
      end
    end

    def by_category(query)
      return query if @params[:category].blank?
      query.joins(:invoice_items).where("invoice_items.category ILIKE ?", "%#{@params[:category]}%")
    end

    def by_seller(query)
      return query if @params[:seller_name].blank?
      query.where("invoices.seller_name ILIKE ?", "%#{@params[:seller_name]}%")
    end

    def by_purchase_date(query)
      return query if @params[:purchase_date].blank?
      query.where(purchase_date: @params[:purchase_date])
    end
  end
end
