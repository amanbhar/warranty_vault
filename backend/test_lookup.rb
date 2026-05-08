require_relative 'config/environment'

brand = "Samsung"
name = "236 L Refrigerator"
model = "RT28T3743S8/HL"

lookup = EnhancedProductLookup.new(brand, name, model)
result = lookup.fetch

if result.is_a?(Hash)
  puts "SUCCESS: Result is a Hash"
  puts "Keys: #{result.keys.join(', ')}"
else
  puts "FAILED: Result is #{result.class}"
end
