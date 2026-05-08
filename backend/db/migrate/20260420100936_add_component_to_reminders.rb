class AddComponentToReminders < ActiveRecord::Migration[8.0]
  def change
    add_column :reminders, :component, :string
    add_index :reminders, :component
  end
end
