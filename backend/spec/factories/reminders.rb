FactoryBot.define do
  factory :reminder do
    association :user
    association :item_warranty
    remind_at { 1.month.from_now }
    reminder_type { :default }
    sent { false }
  end
end
