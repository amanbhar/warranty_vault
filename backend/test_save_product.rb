require_relative 'config/environment'

# Test Samsung lookups to replicate user scenario
brand = "Samsung"
name = "236 L Frost Free Double Door 3 Star Convertible Refrigerator"
model = "RT28T3743S8/HL"

lookup = EnhancedProductLookup.new(brand, name, model)

puts "--- Testing save_product directly ---"
test_data = { category: "appliances", description: "test specs", source: "test" }
saved = lookup.send(:save_product, test_data)
puts "Result of save_product: #{saved.inspect} (Class: #{saved.class})"

if saved.respond_to?(:id)
  puts "SUCCESS: saved_product has ID #{saved.id}"
else
  puts "FAILED: saved_product is NOT an object with ID"
end

puts "\n--- Testing full fetch flow ---"
result = lookup.fetch
if result
  puts "FETCH SUCCESS"
  puts "Result keys: #{result.keys}"
else
  puts "FETCH FAILED (check logs)"
end
