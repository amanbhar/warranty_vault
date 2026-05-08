
# frozen_string_literal: true

token = ARGV[0]
puts "Testing token: #{token}"

# Simulate the request object
class MockRequest
  attr_accessor :query_parameters, :params, :headers, :cookie_jar
  def initialize(token)
    @query_parameters = { "token" => token }
    @params = {}
    @headers = { "Authorization" => "Bearer #{token}" }
    @cookie_jar = {}
  end
  def cookies
    @cookie_jar
  end
end

connection = ApplicationCable::Connection.new(ActionCable.server, {})
mock_request = MockRequest.new(token)

# Define request method on connection
connection.define_singleton_method(:request) { mock_request }

begin
  token_from_query = mock_request.query_parameters["token"]
  payload = JwtService.decode(token_from_query)
  puts "Payload: #{payload.inspect}"

  extracted_token = connection.send(:extract_token_from_params)
  puts "Extracted Token from Params: '#{extracted_token}'"

  user = connection.send(:find_verified_user)
  puts "Found User: #{user.inspect}"
  if user
    puts "SUCCESS: Found user #{user.email} (ID: #{user.id})"
  else
    puts "FAILURE: User not found"
  end
rescue => e
  puts "ERROR: #{e.message}"
  puts e.backtrace.join("\n")
end
