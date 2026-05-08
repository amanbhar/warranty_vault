# frozen_string_literal: true

class ProductChannel < ApplicationCable::Channel
  def subscribed
    reject and return unless current_user
    stream_from "user_#{current_user.id}_products"
    Rails.logger.info "[ProductChannel] User #{current_user.id} subscribed to product updates"
  end

  def unsubscribed
    return unless current_user
    Rails.logger.info "[ProductChannel] User #{current_user.id} unsubscribed from product updates"
  end
end
