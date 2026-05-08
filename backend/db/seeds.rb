# Seeds for Warranty Vault API
# Run with: bin/rails db:seed

puts "🌱 Seeding database for Warranty Vault..."

# Clean existing data
puts "Cleaning existing data..."
GmailConnection.destroy_all
Notification.destroy_all
Invoice.destroy_all
User.destroy_all

# Create demo user
puts "Creating demo user..."
demo_user = User.create!(
  email: "demo@warrantyvault.com",
  password: "Demo@1234",
  first_name: "Demo",
  last_name: "User",
  role: :member,
  last_sign_in_at: Time.current,
  sign_in_count: 1
)

# Create additional test user
test_user = User.create!(
  email: "test@warrantyvault.com",
  password: "Test@1234",
  first_name: "Test",
  last_name: "User",
  role: :member
)

puts "✓ Users created"

# Sample invoice data with invoice_items
invoices_data = [
  {
    invoice_number: "INV-001",
    seller_name: "Apple Store",
    total_amount: 1999.00,
    purchase_date: 3.months.ago,
    warranty_duration: 24,
    expires_at: 3.months.ago + 24.months,
    items: [
      { product_name: "MacBook Pro 14\"", brand: "Apple", model_number: "MP773HN/A", category: "Electronics", price: 1999.00 }
    ]
  },
  {
    invoice_number: "INV-002",
    seller_name: "Amazon",
    total_amount: 349.99,
    purchase_date: 8.months.ago,
    warranty_duration: 12,
    expires_at: 8.months.ago + 12.months,
    items: [
      { product_name: "Sony WH-1000XM5 Headphones", brand: "Sony", model_number: "WH1000XM5", category: "Electronics", price: 349.99 }
    ]
  },
  {
    invoice_number: "INV-003",
    seller_name: "Best Buy",
    total_amount: 2499.00,
    purchase_date: 10.months.ago,
    warranty_duration: 24,
    expires_at: 10.months.ago + 24.months,
    items: [
      { product_name: "Samsung Family Hub Refrigerator", brand: "Samsung", model_number: "RF28R7551SR", category: "Appliances", price: 2499.00 }
    ]
  },
  {
    invoice_number: "INV-004",
    seller_name: "Croma",
    total_amount: 15999.00,
    purchase_date: 2.months.ago,
    warranty_duration: 12,
    expires_at: 2.months.ago + 12.months,
    items: [
      { product_name: "iPhone 15 Pro Max", brand: "Apple", model_number: "iPhone15PM", category: "Electronics", price: 15999.00 }
    ]
  },
  {
    invoice_number: "INV-005",
    seller_name: "Reliance Digital",
    total_amount: 54990.00,
    purchase_date: 15.days.ago,
    warranty_duration: 36,
    expires_at: 15.days.ago + 36.months,
    items: [
      { product_name: "MacBook Air M3", brand: "Apple", model_number: "MacBookAir15", category: "Electronics", price: 54990.00 }
    ]
  },
  {
    invoice_number: "INV-006",
    seller_name: "Williams Sonoma",
    total_amount: 699.95,
    purchase_date: 1.year.ago,
    warranty_duration: 12,
    expires_at: 1.year.ago + 12.months,
    items: [
      { product_name: "Breville Barista Express Espresso Machine", brand: "Breville", model_number: "BES870XL", category: "Appliances", price: 699.95 }
    ]
  },
  {
    invoice_number: "INV-007",
    seller_name: "Herman Miller",
    total_amount: 1445.00,
    purchase_date: 5.months.ago,
    warranty_duration: 120,
    expires_at: 5.months.ago + 120.months,
    items: [
      { product_name: "Herman Miller Aeron Chair", brand: "Herman Miller", model_number: "AERON-B", category: "Furniture", price: 1445.00 }
    ]
  },
  {
    invoice_number: "INV-008",
    seller_name: "B&H Photo",
    total_amount: 2499.00,
    purchase_date: 7.months.ago,
    warranty_duration: 12,
    expires_at: 7.months.ago + 12.months,
    items: [
      { product_name: "Canon EOS R6 Mark II", brand: "Canon", model_number: "R6 Mark II", category: "Electronics", price: 2499.00 }
    ]
  },
  {
    invoice_number: "INV-009",
    seller_name: "Target",
    total_amount: 449.99,
    purchase_date: 2.years.ago,
    warranty_duration: 12,
    expires_at: 2.years.ago + 12.months,
    items: [
      { product_name: "KitchenAid Stand Mixer", brand: "KitchenAid", model_number: "KSM150PSER", category: "Appliances", price: 449.99 }
    ]
  },
  {
    invoice_number: "INV-010",
    seller_name: "Apple Store",
    total_amount: 1099.00,
    purchase_date: 1.month.ago,
    warranty_duration: 12,
    expires_at: 1.month.ago + 12.months,
    items: [
      { product_name: "iPad Pro 12.9\"", brand: "Apple", model_number: "iPadPro12.9", category: "Electronics", price: 1099.00 }
    ]
  },
  {
    invoice_number: "INV-011",
    seller_name: "Home Depot",
    total_amount: 1149.00,
    purchase_date: 9.months.ago,
    warranty_duration: 24,
    expires_at: 9.months.ago + 24.months,
    items: [
      { product_name: "Bosch 800 Series Dishwasher", brand: "Bosch", model_number: "SHP88TZ52N", category: "Appliances", price: 1149.00 }
    ]
  }
]

puts "Creating invoices for demo user..."
invoices_data.each do |data|
  items_data = data.delete(:items)
  invoice = demo_user.invoices.new(data)

  items_data.each do |item_data|
    warranties_data = item_data.delete(:warranties)
    item = invoice.invoice_items.build(item_data)

    if data[:purchase_date] && data[:warranty_duration]
      item.item_warranties.build(
        component_name: "product",
        duration_months: data[:warranty_duration],
        expires_at: data[:purchase_date] + data[:warranty_duration].months
      )
    end
  end

  invoice.save!
end

# Create some general notifications
Notification.create!(
  user: demo_user,
  title: "Welcome to Warranty Vault!",
  message: "Start by uploading your first receipt or connecting your Gmail account.",
  notification_type: :info,
  read: false
)

puts "Creating invoices for test user..."
test_invoices = [
  {
    invoice_number: "TEST-001",
    seller_name: "Dell",
    total_amount: 1799.00,
    purchase_date: 4.months.ago,
    warranty_duration: 24,
    expires_at: 4.months.ago + 24.months,
    items: [
      { product_name: "Dell XPS 15 Laptop", brand: "Dell", model_number: "XPS 15", category: "Electronics", price: 1799.00 }
    ]
  },
  {
    invoice_number: "TEST-002",
    seller_name: "Amazon",
    total_amount: 899.00,
    purchase_date: 6.months.ago,
    warranty_duration: 12,
    expires_at: 6.months.ago + 12.months,
    items: [
      { product_name: "Sonos Arc Soundbar", brand: "Sonos", model_number: "ARC", category: "Electronics", price: 899.00 }
    ]
  }
]

test_invoices.each do |data|
  items_data = data.delete(:items)
  invoice = test_user.invoices.new(data)

  items_data.each do |item_data|
    item = invoice.invoice_items.build(item_data)

    if data[:purchase_date] && data[:warranty_duration]
      item.item_warranties.build(
        component_name: "product",
        duration_months: data[:warranty_duration],
        expires_at: data[:purchase_date] + data[:warranty_duration].months
      )
    end
  end

  invoice.save!
end

puts ""
puts "✅ Seeding complete!"
puts ""
puts "📊 Summary:"
puts "   - Users: #{User.count}"
puts "   - Invoices: #{Invoice.count}"
puts "   - Invoice Items: #{InvoiceItem.count}"
puts "   - Item Warranties: #{ItemWarranty.count}"
puts "   - Notifications: #{Notification.count}"
puts ""
puts "🔐 Demo Credentials:"
puts "   Email: demo@warrantyvault.com"
puts "   Password: Demo@1234"
puts ""
puts "🔐 Test Credentials:"
puts "   Email: test@warrantyvault.com"
puts "   Password: Test@1234"
