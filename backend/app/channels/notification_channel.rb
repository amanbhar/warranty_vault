# frozen_string_literal: true

class NotificationChannel < ApplicationCable::Channel
  def subscribed
    reject and return unless current_user
    # User-specific notification stream
    stream_from "user_#{current_user.id}_notifications"
    Rails.logger.info "[NotificationChannel] User #{current_user.id} subscribed to notifications"
  end

  def unsubscribed
    return unless current_user
    Rails.logger.info "[NotificationChannel] User #{current_user.id} unsubscribed from notifications"
  end

  # Handle marking notification as read
  def mark_as_read(data)
    notification_id = data["notification_id"]

    if notification_id.present?
      result = NotificationService.mark_as_read(notification_id, current_user)

      if result[:success]
        # Broadcast updated unread count
        broadcast_unread_count
        Rails.logger.info "[NotificationChannel] Notification #{notification_id} marked as read"
      else
        Rails.logger.error "[NotificationChannel] Failed to mark notification #{notification_id} as read: #{result[:error]}"
      end
    end
  end

  # Handle marking all notifications as read
  def mark_all_read
    result = NotificationService.mark_all_as_read(current_user)

    if result[:success]
      # Broadcast updated unread count
      broadcast_unread_count
      Rails.logger.info "[NotificationChannel] All notifications marked as read for user #{current_user.id}"
    else
      Rails.logger.error "[NotificationChannel] Failed to mark all notifications as read: #{result[:error]}"
    end
  end

  # Handle fetching unread count
  def fetch_unread_count
    count = NotificationService.unread_count(current_user)

    transmit({
      type: "unread_count_update",
      unread_count: count,
      timestamp: Time.current.iso8601
    })
  end

  private

  def broadcast_unread_count
    count = NotificationService.unread_count(current_user)

    ActionCable.server.broadcast(
      "user_#{current_user.id}_notifications",
      {
        type: "unread_count_update",
        unread_count: count,
        timestamp: Time.current.iso8601
      }
    )
  end
end
