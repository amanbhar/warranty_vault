# frozen_string_literal: true

# DailyEngagementJob — Sends one engagement message per user at 12 PM daily.
#
# Covers: email + in-app notification.
# Deduplication is handled inside NotificationService#send_daily_engagement.
class DailyEngagementJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform
    Rails.logger.info "[DailyEngagementJob] ===== START ====="

    count = 0
    User.where(email_verified: true).find_each do |user|
      NotificationService.send_daily_engagement(user)
      count += 1
    rescue => e
      Rails.logger.error "[DailyEngagementJob] Failed for user #{user.id}: #{e.message}"
    end

    Rails.logger.info "[DailyEngagementJob] ===== DONE ===== processed=#{count}"
  end
end
