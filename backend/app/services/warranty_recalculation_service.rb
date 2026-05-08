# frozen_string_literal: true

class WarrantyRecalculationService
  def self.recalculate_invoice(invoice, purchase_date_changed: false, warranty_changed: false)
    new(invoice).recalculate(purchase_date_changed: purchase_date_changed, warranty_changed: warranty_changed)
  end

  def initialize(invoice)
    @invoice = invoice
  end

  def recalculate(purchase_date_changed: false, warranty_changed: false)
    ActiveRecord::Base.transaction do
      # 2. Recalculate each item and its warranties
      @invoice.invoice_items.each do |item|
        item.item_warranties.each do |warranty|
          # calculate_dates in ItemWarranty now forces sync with invoice.purchase_date
          # if start_date wasn't manually overridden.
          warranty.save!
        end
        # Item status is computed from warranties
        item.save!
      end

      # 3. Update Invoice level aggregated fields
      latest_expiry = @invoice.invoice_items.flat_map(&:item_warranties).map(&:expires_at).compact.max
      computed_invoice_status = WarrantyStatusCalculator.invoice_status(@invoice.invoice_items)

      @invoice.expires_at = latest_expiry
      @invoice.warranty_status = (computed_invoice_status == "expiring" ? :expiring_soon : computed_invoice_status)
      @invoice.save!
    end

    # After transaction commits, reschedule reminders for all items
    reschedule_reminders(purchase_date_changed: purchase_date_changed, warranty_changed: warranty_changed)

    # Broadcast dashboard update via WebSocket
    broadcast_dashboard_update

    @invoice
  end

  private

  def reschedule_reminders(purchase_date_changed:, warranty_changed:)
    # Reminder scheduling is handled by Invoices::Update#run_post_update_events
    # which calls handle_warranty_update with the correct reason.
    # We do nothing here to avoid double-firing.
  end

  def broadcast_dashboard_update
    return unless @invoice.user

    NotificationService.broadcast_dashboard_update(@invoice.user)
  rescue => e
    Rails.logger.error "[WarrantyRecalculationService] Failed to broadcast dashboard update: #{e.message}"
  end
end
