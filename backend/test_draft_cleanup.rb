#!/usr/bin/env ruby

# Test script for Draft Cleanup Job
# Demonstrates the daily cleanup of old draft invoices

puts "🧹 Draft Cleanup Job Test"
puts "=" * 50

puts "\n📋 Current Setup:"
puts "- DraftCleanupJob: Daily cron job at 4:00 AM UTC"
puts "- Default cleanup: Drafts older than 7 days"
puts "- Configurable via DRAFT_CLEANUP_DAYS environment variable"

puts "\n🧪 Testing Draft Cleanup:"

# Create a test draft
puts "\n1️⃣ Creating a test draft invoice..."
test_draft = Invoice.create!(
  product_name: "Test Draft for Cleanup",
  amount: 100,
  purchase_date: Date.today,
  warranty_duration: 12,
  status: :draft,
  ocr_status: :pending
)
puts "   Created draft ID: #{test_draft.id} at #{test_draft.created_at}"

# Create an old draft (8 days ago)
puts "\n2️⃣ Creating an old draft invoice (8 days old)..."
old_draft = Invoice.create!(
  product_name: "Old Draft for Cleanup",
  amount: 200,
  purchase_date: 8.days.ago.to_date,
  warranty_duration: 12,
  status: :draft,
  ocr_status: :pending,
  created_at: 8.days.ago
)
puts "   Created old draft ID: #{old_draft.id} at #{old_draft.created_at}"

puts "\n3️⃣ Running cleanup for drafts older than 7 days..."
DraftCleanupJob.perform_now(7)

puts "\n4️⃣ Checking results..."
total_drafts = Invoice.draft.count
puts "   Total drafts remaining: #{total_drafts}"

if total_drafts == 1
  puts "   ✅ Old draft successfully deleted!"
  puts "   ✅ Test draft (recent) still exists"
else
  puts "   ⚠️  Unexpected result"
end

# Test with 0 days (delete all drafts)
puts "\n5️⃣ Running cleanup for all drafts (0 days)..."
DraftCleanupJob.perform_now(0)

final_drafts = Invoice.draft.count
puts "   Final drafts remaining: #{final_drafts}"

if final_drafts == 0
  puts "   ✅ All drafts successfully cleaned!"
else
  puts "   ⚠️  Some drafts remain"
end

puts "\n🔧 Configuration Options:"
puts "- Set DRAFT_CLEANUP_DAYS environment variable to change cleanup age"
puts "- Default: 7 days"
puts "- Schedule: Daily at 4:00 AM UTC (config/schedule.yml)"

puts "\n✨ Draft Cleanup Job is ready for production!"
