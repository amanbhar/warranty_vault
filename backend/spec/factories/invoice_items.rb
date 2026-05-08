FactoryBot.define do
  factory :invoice_item do
    association :invoice
    product_name { Faker::Commerce.product_name }
    brand { Faker::Company.name }
  end
end
