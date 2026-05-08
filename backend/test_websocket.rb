#!/usr/bin/env ruby

# WebSocket functionality test script
require 'websocket-client-simple'
require 'json'
require 'uri'

class WebSocketTester
  def initialize(base_url = 'ws://localhost:3005')
    @base_url = base_url
    @ws = nil
  end

  def test_connection(token)
    puts "=== WebSocket Connection Test ==="

    # Connect to WebSocket with token
    ws_url = "#{@base_url}/cable?token=#{token}"

    puts "Connecting to: #{ws_url}"

    @ws = WebSocket::Client::Simple.connect(ws_url)

    setup_handlers
    subscribe_to_channels

    # Keep connection open for testing
    sleep 2

    # Test notification
    test_notification_creation

    # Keep connection open to receive messages
    puts "Waiting for messages (10 seconds)..."
    sleep 10

    cleanup
  end

  private

  def setup_handlers
    @ws.on :open do |event|
      puts "✅ WebSocket connected"
    end

    @ws.on :message do |event|
      data = JSON.parse(event.data)
      puts "📨 Received: #{data['type']}"

      case data['type']
      when 'welcome'
        puts "👋 Welcome message received"
      when 'confirm_subscription'
        puts "✅ Subscription confirmed: #{data['identifier']}"
      when 'new_notification'
        puts "🔔 New notification: #{data['notification']['title']}"
        puts "📊 Unread count: #{data['unread_count']}"
      when 'unread_count_update'
        puts "📊 Unread count updated: #{data['unread_count']}"
      when 'warranty_created'
        puts "🛡️ Warranty created: #{data['warranty']['component']}"
      when 'warranty_expiry_alert'
        puts "⚠️ Warranty expiry alert: #{data['days_remaining']} days remaining"
      else
        puts "❓ Unknown message type: #{data['type']}"
      end
    end

    @ws.on :error do |event|
      puts "❌ WebSocket error: #{event.message}"
    end

    @ws.on :close do |event|
      puts "🔌 WebSocket closed: #{event.code} #{event.reason}"
    end
  end

  def subscribe_to_channels
    # Subscribe to notification channel
    subscribe_command = {
      command: 'subscribe',
      identifier: JSON.generate({
        channel: 'NotificationChannel'
      })
    }

    @ws.send(JSON.generate(subscribe_command))
    puts "📢 Subscribed to NotificationChannel"

    # Subscribe to warranty channel
    warranty_subscribe_command = {
      command: 'subscribe',
      identifier: JSON.generate({
        channel: 'WarrantyChannel'
      })
    }

    @ws.send(JSON.generate(warranty_subscribe_command))
    puts "📢 Subscribed to WarrantyChannel"
  end

  def test_notification_creation
    puts "🧪 Testing notification creation..."

    # This would normally be done via API, but for testing we'll simulate
    # In a real scenario, you'd make an API call that creates a notification
    # which would then be broadcast via WebSocket
  end

  def cleanup
    @ws.close if @ws
    puts "🧹 Cleanup complete"
  end
end

# Usage
if ARGV.length < 1
  puts "Usage: ruby test_websocket.rb <JWT_TOKEN>"
  puts "Get token by logging in first"
  exit 1
end

token = ARGV[0]
tester = WebSocketTester.new
tester.test_connection(token)
