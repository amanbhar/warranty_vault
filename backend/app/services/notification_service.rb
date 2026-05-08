# frozen_string_literal: true

# ============================================================
# NotificationService — Senior Implementation
#
# Clean, event-driven, and idempotent notification hub.
# All notification logic is consolidated here.
# ============================================================
class NotificationService
  FRONTEND_URL       = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
  DEFAULT_MILESTONES = [ 30, 7, 1 ].freeze

  class << self
    # ----------------------------------------------------------
    # 1. TRIGGER: NEW INVOICE
    # ----------------------------------------------------------
    def handle_invoice_created(items)
      items = Array(items)
      return if items.empty?

      invoice = items.first.invoice
      user    = invoice.user
      return unless user

      items.each do |item|
        # Initial confirmation notification
        fire_notification(
          user,
          title:   "Product Added",
          message: "Your #{item.product_name} has been added to the vault.",
          type:    "invoice_created",
          item:    item,
          meta:    { event: "invoice_created", invoice_id: invoice.id }
        )

        # Triggers fresh reminder generation
        handle_warranty_update(item)
      end
    end

    # ----------------------------------------------------------
    # 2. TRIGGER: WARRANTY UPDATE (Senior Logic)
    # ----------------------------------------------------------
    def handle_warranty_update(item, reason: :warranty_update, warranty_id: nil)
      user = item.invoice&.user
      return unless user

      # STEP 1: Recalculate expiry_date for ALL warranties of item
      item.item_warranties.each do |warranty|
        # trigger before_validation :calculate_dates
        warranty.save(validate: false)
      end

      # STEP 2: DELETE all existing reminders for warranties of this item
      warranty_ids = item.item_warranties.pluck(:id)
      # First mark pending ones as sent to prevent race condition with Sidekiq
      Reminder.where(item_warranty_id: warranty_ids, sent: false).update_all(sent: true, sent_at: Time.current)
      # Then delete all sent reminders
      Reminder.where(item_warranty_id: warranty_ids, sent: true).delete_all

      # STEP 3 & 4: RECREATE reminders + Check immediate condition
      schedule_reminders_for_item(user, item, warranty_id: warranty_id)

      # STEP 5: Send confirmation notification for purchase_date or warranty changes
      if reason == :purchase_date_changed
        new_purchase_date = item.invoice.purchase_date
        new_expires_at = item.item_warranties.map(&:expires_at).compact.min
        fire_notification(
          user,
          title: "Purchase Date Updated",
          message: "Your #{item.product_name} purchase date was updated to #{new_purchase_date.strftime('%B %d, %Y')}. Warranty expires on #{new_expires_at&.strftime('%B %d, %Y')}. Your reminders have been rescheduled.",
          type: "invoice_updated",
          item: item,
          meta: { event: "purchase_date_updated", reason: reason }
        )
      elsif reason == :warranty_changed
        warranty = item.item_warranties.find_by(id: warranty_id) || item.item_warranties.first
        new_expires_at = warranty&.expires_at
        component_name = warranty&.component_display_name || "product"
        duration_months = warranty&.duration_months
        fire_notification(
          user,
          title: "Warranty Updated",
          message: "Your #{item.product_name} (#{component_name}) warranty has been updated to #{duration_months} months. It now expires on #{new_expires_at&.strftime('%B %d, %Y')}. Your reminders have been rescheduled.",
          type: "invoice_updated",
          item: item,
          meta: { event: "warranty_updated", reason: reason, component: warranty&.component_name }
        )
      end
    end

    # ----------------------------------------------------------
    # 3. TRIGGER: CUSTOM REMINDER PREFERENCE ADDED
    # ----------------------------------------------------------
    def apply_custom_reminder(user, days)
      days = days.to_i
      return unless days.positive?

      user.invoice_items.find_each do |item|
        # Simply refresh this item's reminder set
        handle_warranty_update(item)
      end
    end

    # ----------------------------------------------------------
    # 4. TRIGGER: CUSTOM REMINDER PREFERENCE REMOVED
    # ----------------------------------------------------------
    def remove_custom_reminder(user, days)
      # Refresh everything to stay clean as per "frequent refresh" spec
      user.invoice_items.find_each { |item| handle_warranty_update(item) }
    end

    # ----------------------------------------------------------
    # 5. SCHEDULER: HOURLY DISPATCH
    # ----------------------------------------------------------
    def process_due_reminders
      reminders = Reminder.pending.due
      stats = { due: reminders.count, sent: 0, failed: 0 }

      reminders.includes(item_warranty: { invoice_item: { invoice: :user } }).find_each do |reminder|
        if dispatch_reminder(reminder)
          stats[:sent] += 1
        else
          stats[:failed] += 1
        end
      end

      stats
    end

    # ----------------------------------------------------------
    # 6. DAILY ENGAGEMENT (NOON)
    # ----------------------------------------------------------
    def send_daily_engagement(user)
      return unless user&.email_verified?

      already_sent = user.notifications
                         .where(notification_type: "daily_engagement")
                         .where("created_at >= ?", Time.current.beginning_of_day)
                         .exists?
      return if already_sent

      fire_notification(
        user,
        title:   "Vault Update",
        message: "You have #{user.invoices.processed.count} products in your vault. Check your status.",
        type:    "daily_engagement",
        meta:    { event: "daily_engagement" }
      )
    end

    # ----------------------------------------------------------
    # 7. HELPERS: IN-APP + EMAIL (SYNC)
    # ----------------------------------------------------------
    def fire_notification(user, title:, message:, type: "info", item: nil, meta: {}, **options)
      # Unified In-App Creation (including WebSocket broadcast)
      notif = create_in_app(
        user,
        title: title,
        message: message,
        type: type,
        url: item ? item_url(item) : "#{FRONTEND_URL}/dashboard",
        meta: meta.merge(invoice_item_id: item&.id).compact
      )

      # Unified Email Enqueue
      if notif && user.email_verified?
        EmailWorker.perform_async(notif.id)
      end

      notif
    end

    def broadcast_dashboard_update(user)
      return unless user
      ActionCable.server.broadcast(
        "user_#{user.id}_notifications",
        {
          type:      "dashboard_updated",
          timestamp: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.error "[NotificationService] broadcast_dashboard_update failed: #{e.message}"
    end
    def schedule_reminders_for_item(user, item, warranty_id: nil)
      milestones = (DEFAULT_MILESTONES + custom_days_for(user))
                     .map(&:to_i)
                     .select(&:positive?)
                     .uniq
                     .sort
                     .reverse

      warranties = item.item_warranties
      warranties = warranties.where(id: warranty_id) if warranty_id.present?

      warranties.each do |warranty|
        next unless warranty.expires_at
        break if reminder_capacity_reached?(warranty)

        past_milestones = []
        future_milestones = []

        milestones.each do |days|
          remind_at = (warranty.expires_at - days.days).to_time.in_time_zone.end_of_day
          if remind_at <= Time.current
            past_milestones << days
          else
            future_milestones << days
          end
        end

        # Schedule all future milestones normally
        future_milestones.each do |days|
          break if reminder_capacity_reached?(warranty)
          remind_at = (warranty.expires_at - days.days).to_time.in_time_zone.end_of_day
          next if remind_at.to_date > warranty.expires_at.to_date
          upsert_future_reminder(user, warranty, remind_at, days)
        end

        # For past milestones: fire ONLY the most relevant one (smallest days = closest to today)
        # Mark the rest as sent without firing so the scheduler skips them
        if past_milestones.any?
          # sort ascending so smallest days (closest to today) is first
          sorted = past_milestones.sort

          # Fire only the most relevant one
          trigger_immediate_fire(user, warranty, sorted.first)

          # Silently record the rest as already sent (no notification, no email)
          sorted.drop(1).each do |days|
            break if reminder_capacity_reached?(warranty)
            Reminder.create!(
              user:          user,
              item_warranty: warranty,
              remind_at:     (warranty.expires_at - days.days).to_time.in_time_zone.end_of_day,
              reminder_type: DEFAULT_MILESTONES.include?(days) ? :default : :custom,
              sent:          true,
              sent_at:       Time.current
            )
          rescue ActiveRecord::RecordNotUnique
            # already exists, skip
          end
        end
      end
    end


    # ----------------------------------------------------------
    # MANAGEMENT & PUBLIC API
    # ----------------------------------------------------------
    def unread_count(user); user.unread_notification_count; end

    def get_notifications(user, options = {})
      page       = (options[:page] || 1).to_i
      per_page   = (options[:per_page] || 20).to_i
      scope      = user.notifications
      scope      = scope.where(read: false)                          if options[:unread_only]
      scope      = scope.where(notification_type: options[:type])   if options[:type]

      total = scope.count
      list  = scope.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

      {
        notifications: list,
        unread_count:  unread_count(user),
        pagination:    {
          current_page: page,
          total_pages:  (total.to_f / per_page).ceil,
          total_count:  total,
          per_page:     per_page
        }
      }
    end

    def delete_notification(id, user)
      n = user.notifications.find_by(id: id)
      n&.destroy
      { success: !!n }
    end

    def mark_as_read(id, user); n = user.notifications.find_by(id: id); n&.update(read: true); { success: !!n, notification: n }; end
    def mark_all_as_read(user); count = user.notifications.where(read: false).update_all(read: true); { success: true, count: count }; end
    def notify_item_updated(item); fire_notification(item.invoice.user, title: "Product Updated", message: "#{item.product_name} was updated. Your warranty reminders have been rescheduled.", type: "product_updated", item: item); end
    def handle_login(user); fire_notification(user, title: "Login Successful", message: "Welcome back.", type: "info"); end
    def handle_signup(user); fire_notification(user, title: "Welcome!", message: "Account ready.", type: "info"); EmailWorker.perform_async(nil, user_id: user.id, email_type: :verification); end

    private

    def trigger_immediate_fire(user, warranty, days)
      return if reminder_capacity_reached?(warranty)

      item = warranty.invoice_item
      # Calculate actual days remaining from warranty expiry
      actual_days = warranty.expires_at ? [ (warranty.expires_at.to_date - Date.current).to_i, 0 ].max : 0
      type = actual_days <= 0 ? "warranty_expired" : "warranty_expiring"

      # Use fire_notification which calls create_in_app (has deduplication logic)
      fire_notification(
        user,
        title:   "Warranty Alert",
        message: warranty_alert_message(item.product_name, warranty.component_display_name, actual_days),
        type:    type,
        item:    item,
        meta:    {
          event: "warranty_reminder",
          component: warranty.component_name,
          days_remaining: actual_days,
          milestone: days
        }
      )

      # Create record as sent so scheduler ignores it
      Reminder.create!(
        user:          user,
        item_warranty: warranty,
        remind_at:     Time.current,
        reminder_type: DEFAULT_MILESTONES.include?(days) ? :default : :custom,
        sent:          true,
        sent_at:       Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      # Already recorded, skip
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "[NotificationService] Skipping sent reminder create " \
        "warranty_id=#{warranty&.id} user_id=#{user&.id} component=#{warranty&.component_name} " \
        "errors=#{e.record.errors.full_messages.join(', ')}"
      )
    end

    def upsert_future_reminder(user, warranty, remind_at, days)
      return if reminder_capacity_reached?(warranty)
      return if remind_at.to_date > warranty.expires_at.to_date

      Reminder.create!(
        user:          user,
        item_warranty: warranty,
        remind_at:     remind_at,
        reminder_type: DEFAULT_MILESTONES.include?(days) ? :default : :custom,
        sent:          false
      )
    rescue ActiveRecord::RecordNotUnique
      # Already exists, skip
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn(
        "[NotificationService] Skipping future reminder upsert " \
        "warranty_id=#{warranty&.id} user_id=#{user&.id} component=#{warranty&.component_name} " \
        "remind_at=#{remind_at} reminder_type=#{DEFAULT_MILESTONES.include?(days) ? :default : :custom} " \
        "errors=#{e.record.errors.full_messages.join(', ')}"
      )
    end

    def reminder_capacity_reached?(warranty)
      warranty.reminders.count >= 5
    end

    def dispatch_reminder(reminder)
      reminder.with_lock do
        return false if reminder.sent?

        # Stale check: if a newer unsent reminder exists for same warranty+type,
        # this one is outdated — skip it
        newer_exists = Reminder.where(
          item_warranty_id: reminder.item_warranty_id,
          reminder_type: reminder.reminder_type,
          sent: false
        ).where("created_at > ? AND id != ?", reminder.created_at, reminder.id).exists?

        if newer_exists
          reminder.update!(sent: true, sent_at: Time.current)
          Rails.logger.info "[NotificationService] Skipping stale reminder #{reminder.id} — newer reminder exists"
          return false
        end

        warranty = reminder.item_warranty
        item     = warranty.invoice_item
        days     = warranty ? [(warranty.expires_at.to_date - Date.current).to_i, 0].max : 0

        fire_notification(
          reminder.user,
          title:   "Warranty Alert",
          message: warranty_alert_message(item.product_name, warranty.component_display_name, days),
          type:    days <= 0 ? "warranty_expired" : "warranty_expiring",
          item:    item,
          meta:    { 
            event: "warranty_reminder", 
            component: warranty.component_name, 
            warranty_id: warranty.id,
            days_remaining: days 
          }
        )

        reminder.update!(sent: true, sent_at: Time.current)
        true
      end
    rescue => e
      Rails.logger.error "[NotificationService] dispatch_reminder #{reminder.id} failed: #{e.message}"
      false
    end

    def create_in_app(user, title:, message:, type: "info", url: nil, meta: {})
      # Deduplication logic (Senior level)
      # Prevent same notification within 1 hour for exact same item/event/reason
      recent = user.notifications
                   .where(notification_type: type)
                   .where("metadata ->> 'invoice_item_id' = ?", meta[:invoice_item_id].to_s)
                   .where("metadata ->> 'event' = ?", meta[:event].to_s)
                   .where("metadata ->> 'reason' = ?", meta[:reason].to_s)
                   .where("metadata ->> 'component' = ?", meta[:component].to_s)
                   .where("created_at > ?", 1.hour.ago)
                   .exists? if meta[:invoice_item_id] && meta[:event]

      return nil if recent

      notif = user.notifications.create!(
        title: title, message: message, notification_type: type,
        action_url: url, metadata: meta
      )

      broadcast(user, notif)
      notif
    end

    def broadcast(user, notification)
      ActionCable.server.broadcast(
        "user_#{user.id}_notifications",
        {
          type:         "new_notification",
          event:        "notification_created",
          notification: serialize(notification),
          unread_count: user.unread_notification_count
        }
      )
    end

    def warranty_alert_message(product, component, days)
      comp_str = component.present? ? " (#{component})" : ""
      if days <= 0
        "Your #{product}#{comp_str} warranty has expired."
      elsif days == 1
        "Your #{product}#{comp_str} warranty expires tomorrow."
      else
        "Your #{product}#{comp_str} warranty expires in #{days} days."
      end
    end

    def custom_days_for(user)
      user.user_reminder_preferences.where(reminder_type: :custom).pluck(:days_before_expiry)
    end

    def item_url(item)
      "#{FRONTEND_URL}/invoice/#{item.invoice.id}"
    end

    def serialize(notif)
      {
        id: notif.id, title: notif.title, message: notif.message,
        type: notif.notification_type, url: notif.action_url,
        read: notif.read, created_at: notif.created_at.iso8601
      }
    end
  end
end
