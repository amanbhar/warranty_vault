# frozen_string_literal: true

class ProductBroadcastService
  class << self
    def broadcast_update_to(user, payload = {})
      return unless defined?(ActionCable) && user

      ActionCable.server.broadcast(
        "user_#{user.id}_products",
        {
          type: "product_updated",
          payload: payload,
          timestamp: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.error "[ProductBroadcastService] Failed to broadcast product update for user #{user.id}: #{e.message}"
    end
  end
end
