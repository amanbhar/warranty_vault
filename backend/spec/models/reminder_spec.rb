require 'rails_helper'

RSpec.describe Reminder, type: :model do
  let(:user) { create(:user) }
  let(:invoice) { create(:invoice, user: user) }
  let(:item) { create(:invoice_item, invoice: invoice) }
  let(:warranty) { create(:item_warranty, invoice_item: item, component_name: "product") }
  
  it "belongs to item_warranty" do
    reminder = create(:reminder, user: user, item_warranty: warranty)
    expect(reminder.item_warranty).to eq(warranty)
    expect(reminder.invoice_item).to eq(item) # through association
  end
  
  it "validates uniqueness per user, warranty, and reminder_type" do
    create(:reminder, user: user, item_warranty: warranty, reminder_type: :default)
    duplicate = build(:reminder, user: user, item_warranty: warranty, reminder_type: :default)
    expect(duplicate).not_to be_valid
  end

  it "validates item_warranty_id presence" do
    reminder = build(:reminder, item_warranty: nil)
    expect(reminder).not_to be_valid
    expect(reminder.errors[:item_warranty_id]).to include("can't be blank")
  end

  it "has for_warranty scope" do
    warranty = create(:item_warranty, invoice_item: item)
    reminder = create(:reminder, user: user, item_warranty: warranty, reminder_type: :default)
    expect(Reminder.for_warranty(warranty.id)).to include(reminder)
  end
end
