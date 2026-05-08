# frozen_string_literal: true

# Dashboard channel for real-time updates
# Broadcasts changes to dashboard data (stats, upcoming_expirations)
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    reject and return unless current_user
    # User-specific dashboard stream
    stream_from "user_#{current_user.id}_dashboard"
    Rails.logger.info "[DashboardChannel] User #{current_user.id} subscribed to dashboard updates"
  end

  def unsubscribed
    return unless current_user
    Rails.logger.info "[DashboardChannel] User #{current_user.id} unsubscribed from dashboard updates"
  end

  # Handle request for dashboard data refresh
  def refresh
    data = Invoices::DashboardQuery.new(user: current_user).call

    transmit({
      type: "dashboard_update",
      summary: data[:summary],
      upcoming_expirations: data[:upcoming_expirations],
      timestamp: Time.current.iso8601
    })
  end
end
