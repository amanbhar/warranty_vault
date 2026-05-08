require_relative 'config/environment'
require 'sidekiq/api'

# Test scheduling logic with pending status
user = User.first || User.create!(email: "test@example.com", password: "password123")

puts "--- Testing Manual Entry (Pending Status) ---"
invoice = user.invoices.create!(
  product_name: "Test Pending",
  brand: "Test Brand",
  purchase_date: Date.today,
  warranty_duration: 12,
  category: "electronics",
  ocr_status: "pending" # default
)

# Create a warranty component manually
warranty = invoice.product_warranties.create!(
  component_name: "product",
  warranty_months: 12,
  expires_at: Date.today + 1.year
)

# Check Sidekiq
ss = Sidekiq::ScheduledSet.new
job = ss.find { |j| j.args.first["arguments"].first == warranty.id }

if job
  puts "SUCCESS: WarrantyReminderJob found in Sidekiq ScheduledSet even with Pending status!"
else
  puts "FAILED: No WarrantyReminderJob found."
end

# Clean up
warranty.destroy
invoice.destroy
