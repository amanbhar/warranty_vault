FactoryBot.define do
  factory :item_warranty do
    component_name { "product" }
    duration_months { 12 }
    invoice_item
    
    after(:build) do |warranty|
      warranty.start_date = warranty.invoice_item&.invoice&.purchase_date || Date.current
      warranty.expires_at = warranty.start_date + warranty.duration_months.months
    end
  end
end
