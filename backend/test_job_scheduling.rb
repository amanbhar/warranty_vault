require_relative 'config/environment'
require 'sidekiq/api'

# Test scheduling logic for manual entry
user = User.first || User.create!(email: "test@example.com", password: "password123")

puts "--- Testing Manual Entry Scheduling ---"
invoice = user.invoices.create!(
  product_name: "Test Product",
  brand: "Test Brand",
  purchase_date: Date.today,
  warranty_duration: 12,
  category: "electronics",
  ocr_status: "completed" # simulate manual entry completion
)

puts "Invoice created: ID=#{invoice.id}, status=#{invoice.ocr_status}"

# Create a warranty component manually
# This should trigger ProductWarranty after_save -> WarrantyReminderService -> WarrantyReminderJob
warranty = invoice.product_warranties.create!(
  component_name: "product",
  warranty_months: 12,
  expires_at: Date.today + 1.year
)

puts "ProductWarranty created: ID=#{warranty.id}, expires_at=#{warranty.expires_at}"

# Check Sidekiq ScheduledSet
ss = Sidekiq::ScheduledSet.new
job = ss.find { |j| j.args.first["arguments"].first == warranty.id }

if job
  puts "SUCCESS: WarrantyReminderJob found in Sidekiq ScheduledSet!"
  puts "Job details: #{job.inspect}"
  puts "Wait until: #{Time.at(job.at)}"
else
  # Check if it was sent immediately (if reminder_date <= now)
  rs = Sidekiq::Queue.new("default")
  job = rs.find { |j| j.args.first["arguments"].first == warranty.id }

  if job
    puts "SUCCESS: WarrantyReminderJob found in Sidekiq Default Queue (Immediate)!"
  else
    puts "FAILED: No WarrantyReminderJob found in Sidekiq."
  end
end

# Clean up
warranty.destroy
invoice.destroy
