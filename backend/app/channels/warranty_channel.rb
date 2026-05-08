# frozen_string_literal: true

class WarrantyChannel < ApplicationCable::Channel
  def subscribed
    reject and return unless current_user
    # User-specific warranty updates stream
    stream_from "user_#{current_user.id}_warranties"
    Rails.logger.info "[WarrantyChannel] User #{current_user.id} subscribed to warranty updates"
  end

  def unsubscribed
    return unless current_user
    Rails.logger.info "[WarrantyChannel] User #{current_user.id} unsubscribed from warranty updates"
  end

  # Handle warranty status updates
  def warranty_status_update(data)
    warranty_id = data["warranty_id"]
    status = data["status"]

    if warranty_id.present? && status.present?
      # Broadcast warranty status update
      ActionCable.server.broadcast(
        "user_#{current_user.id}_warranties",
        {
          type: "warranty_status_update",
          warranty_id: warranty_id,
          status: status,
          timestamp: Time.current.iso8601
        }
      )

      Rails.logger.info "[WarrantyChannel] Warranty #{warranty_id} status updated to #{status}"
    end
  end

  # Handle warranty expiry alerts
  def broadcast_expiry_alert(warranty, days_remaining)
    return unless warranty && current_user.id == warranty.invoice.user_id

    ActionCable.server.broadcast(
      "user_#{current_user.id}_warranties",
      {
        type: "warranty_expiry_alert",
        warranty: {
          id: warranty.id,
          product_name: warranty.invoice.product_name,
          component: warranty.component_display_name,
          expires_at: warranty.expires_at,
          days_remaining: days_remaining
        },
        urgency: calculate_urgency(days_remaining),
        timestamp: Time.current.iso8601
      }
    )
  end

  # Handle new warranty creation
  def broadcast_warranty_created(warranty)
    return unless warranty && current_user.id == warranty.invoice.user_id

    ActionCable.server.broadcast(
      "user_#{current_user.id}_warranties",
      {
        type: "warranty_created",
        warranty: {
          id: warranty.id,
          product_name: warranty.invoice.product_name,
          component: warranty.component_display_name,
          expires_at: warranty.expires_at,
          status: warranty.warranty_status
        },
        timestamp: Time.current.iso8601
      }
    )
  end

  private

  def calculate_urgency(days_remaining)
    case days_remaining
    when 0..7
      "critical"
    when 8..30
      "warning"
    when 31..90
      "info"
    else
      "low"
    end
  end
end
