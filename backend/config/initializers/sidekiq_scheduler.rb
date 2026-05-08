# frozen_string_literal: true

# Sidekiq Scheduler configuration for recurring jobs
# This initializer manages the clock for background tasks.
#
# Architecture Rules:
#   • process_due_reminders — Hourly warranty reminder dispatcher
#   • daily_engagement      — 12 PM daily engagement nudge
#
require "sidekiq-scheduler"

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Scheduler.enabled = true
    Sidekiq.schedule = {
      # ── WARRANTY REMINDERS (Every hour) ────────────────────────
      "process_due_reminders" => {
        "cron"        => "0 * * * *",
        "class"       => "ProcessDueRemindersJob",
        "queue"       => "high_priority",
        "description" => "Process due warranty reminders (Hourly entry point)"
      },

      # ── DAILY ENGAGEMENT (Every day at 12 PM UTC) ───────────────
      "daily_engagement" => {
        "cron"        => "0 12 * * *",
        "class"       => "DailyEngagementJob",
        "queue"       => "default",
        "description" => "Send daily engagement message to all users at noon"
      },

      # ── MAINTENANCE (Cleanup) ───────────────────────────────────
      "cleanup_expired_tokens" => {
        "cron"        => "0 */6 * * *",
        "class"       => "TokenCleanupJob",
        "queue"       => "maintenance",
        "description" => "Clean up expired verification tokens (Every 6h)"
      },

      "cleanup_old_notifications" => {
        "cron"        => "0 3 * * *",
        "class"       => "NotificationCleanupJob",
        "queue"       => "maintenance",
        "description" => "Delete notifications older than 30 days (Daily at 3 AM)"
      }
    }

    Sidekiq::Scheduler.reload_schedule!
    Rails.logger.info "[SidekiqScheduler] Loaded unified recurring schedule: #{Sidekiq.schedule.keys.join(', ')}"
  end
end
