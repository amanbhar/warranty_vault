# Calculates warranty expiry dates and schedules reminder jobs
class WarrantyCalculationService
  attr_reader :invoice

  def initialize(invoice)
    @invoice = invoice
  end

  # Schedule reminder jobs for all warranties on this invoice
  def schedule_reminders
    @invoice.invoice_items.includes(:item_warranties).find_each do |item|
      item.item_warranties.find_each do |warranty|
        schedule_warranty_reminder(warranty)
      end
    end

    Rails.logger.info "[WarrantyCalculation] Scheduled reminders for #{@invoice.invoice_items.sum(&:item_warranties).count} warranties"
  end

  # Calculate expiry date for a warranty
  def calculate_expiry(purchase_date, warranty_months)
    return nil unless purchase_date && warranty_months
    purchase_date + warranty_months.months
  end

  # Get days until expiry
  def days_until_expiry(expires_at)
    return nil unless expires_at
    (expires_at - Date.current).to_i
  end

  # Check if warranty is expiring soon
  def expiring_soon?(expires_at, threshold_days = 30)
    days = days_until_expiry(expires_at)
    days && days >= 0 && days <= threshold_days
  end

  private

  # Schedule a reminder job for a specific warranty
  def schedule_warranty_reminder(warranty)
    return unless warranty.expires_at
    return if warranty.expired?

    # Calculate when to send reminder (1 month before expiry)
    reminder_date = warranty.expires_at - 1.month

    # Don't schedule if reminder date is in the past
    if reminder_date <= Date.current
      # Send immediate notification if already past reminder date
      send_immediate_reminder(warranty)
    else
      # Schedule future reminder
      WarrantyReminderJob.set(wait_until: reminder_date.beginning_of_day).perform_later(warranty.id)
      Rails.logger.info "[WarrantyCalculation] Scheduled reminder for warranty #{warranty.id} on #{reminder_date}"
    end
  end

  # Send immediate reminder for warranties close to expiry
  def send_immediate_reminder(warranty)
    return if warranty.reminder_sent

    WarrantyReminderJob.perform_later(warranty.id)
    Rails.logger.info "[WarrantyCalculation] Sending immediate reminder for warranty #{warranty.id}"
  end
end
