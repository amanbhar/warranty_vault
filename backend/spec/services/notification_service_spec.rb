require 'rails_helper'

RSpec.describe NotificationService, type: :service do
  let!(:user) { create(:user) }
  let!(:invoice) { create(:invoice, user: user, purchase_date: Date.current) }
  let!(:item) { create(:invoice_item, invoice: invoice) }
  let!(:warranty) { create(:item_warranty, invoice_item: item, duration_months: 12) }

  describe '.handle_warranty_update' do
    it 'recalculates warranty expiry dates' do
      warranty.update!(expires_at: nil)
      NotificationService.handle_warranty_update(item)
      warranty.reload
      expect(warranty.expires_at).to be_present
    end

    it 'deletes existing pending reminders for warranties' do
      pending_reminder = create(:reminder, user: user, item_warranty: warranty, sent: false)
      warranty_ids = item.item_warranties.pluck(:id)
      
      NotificationService.handle_warranty_update(item)
      
      expect(Reminder.exists?(pending_reminder.id)).to be false
    end
  end

  describe '.reminder_capacity_reached?' do
    let(:warranty) { create(:item_warranty) }

    it 'returns true when 5 reminders exist' do
      5.times { create(:reminder, item_warranty: warranty, sent: true) }
      expect(NotificationService.send(:reminder_capacity_reached?, warranty)).to be true
    end

    it 'returns false when less than 5 reminders exist' do
      3.times { create(:reminder, item_warranty: warranty, sent: true) }
      expect(NotificationService.send(:reminder_capacity_reached?, warranty)).to be false
    end
  end

  describe '.trigger_immediate_fire' do
    it 'creates a sent reminder record' do
      expect {
        NotificationService.send(:trigger_immediate_fire, user, warranty, 7)
      }.to change(Reminder, :count).by(1)
      reminder = Reminder.last
      expect(reminder.sent).to be true
      expect(reminder.item_warranty).to eq(warranty)
    end
  end

  describe '.upsert_future_reminder' do
    it 'creates a pending reminder record' do
      remind_at = warranty.expires_at - 7.days
      expect {
        NotificationService.send(:upsert_future_reminder, user, warranty, remind_at, 7)
      }.to change(Reminder, :count).by(1)
      reminder = Reminder.last
      expect(reminder.sent).to be false
      expect(reminder.item_warranty).to eq(warranty)
    end
  end
end
