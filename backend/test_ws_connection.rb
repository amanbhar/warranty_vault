
require 'faye/websocket'
require 'eventmachine'
require 'json'

# This script tests the ActionCable connection with a given token
token = ARGV[0]
if token.nil?
  puts "Usage: ruby test_ws_connection.rb <jwt_token>"
  exit 1
end

EM.run {
  url = "ws://localhost:3005/cable?token=#{token}"
  puts "Connecting to #{url}..."

  ws = Faye::WebSocket::Client.new(url)

  ws.on :open do |event|
    puts "Connected!"
    # Subscribe to NotificationChannel
    subscribe_msg = {
      command: "subscribe",
      identifier: { channel: "NotificationChannel" }.to_json
    }.to_json
    ws.send(subscribe_msg)
  end

  ws.on :message do |event|
    puts "Received: #{event.data}"
  end

  ws.on :close do |event|
    puts "Closed: #{event.code} #{event.reason}"
    EM.stop
  end

  # Stop after 5 seconds
  EM.add_timer(5) {
    puts "Timed out"
    ws.close
    EM.stop
  }
}
