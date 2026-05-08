FactoryBot.define do
  factory :invoice do
    association :user
    seller_name { Faker::Company.name }
    purchase_date { Date.today }
    total_amount { Faker::Commerce.price }
    status { :draft }
  end
end
