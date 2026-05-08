class ChangeRemindersToWarrantyLevel < ActiveRecord::Migration[7.0]
  def up
    # Step 1: Add item_warranty_id column
    add_reference :reminders, :item_warranty, foreign_key: true, null: true
    
    # Step 2: Migrate existing data - link reminders to warranties via component name
    execute <<-SQL.squish
      UPDATE reminders
      SET item_warranty_id = iw.id
      FROM item_warranties iw
      WHERE reminders.invoice_item_id = iw.invoice_item_id
        AND iw.component_name = reminders.component
        AND reminders.component IS NOT NULL
        AND reminders.item_warranty_id IS NULL
    SQL
    
    # Step 3: For reminders with no matching warranty, try to match by invoice_item
    execute <<-SQL.squish
      UPDATE reminders
      SET item_warranty_id = (
        SELECT iw.id FROM item_warranties iw
        WHERE iw.invoice_item_id = reminders.invoice_item_id
        ORDER BY iw.created_at ASC
        LIMIT 1
      )
      WHERE reminders.item_warranty_id IS NULL
        AND reminders.invoice_item_id IS NOT NULL
    SQL
    
    # Step 4: Remove old unique index
    remove_index :reminders, name: "index_reminders_unique_per_item_type_time"
    remove_index :reminders, name: "idx_unique_reminders_v3"
    remove_index :reminders, name: "index_reminders_on_invoice_item_id"
    
    # Step 5: Deduplicate reminders before making item_warranty_id NOT NULL
    # Keep the most recent reminder for each user/warranty/type combination
    execute <<-SQL.squish
      DELETE FROM reminders
      WHERE id NOT IN (
        SELECT DISTINCT ON (user_id, item_warranty_id, reminder_type) id
        FROM reminders
        ORDER BY user_id, item_warranty_id, reminder_type, 
                 CASE WHEN sent_at IS NOT NULL THEN 1 ELSE 0 END DESC,
                 created_at DESC
      )
    SQL
    
    # Step 6: Make item_warranty_id NOT NULL after data migration
    change_column_null :reminders, :item_warranty_id, false
    
    # Step 7: Remove old invoice_item_id column
    remove_reference :reminders, :invoice_item
    
    # Step 8: Add new unique index for warranty-level reminders
    add_index :reminders, [:user_id, :item_warranty_id, :reminder_type], 
              unique: true, name: "idx_unique_reminders_warranty"
  end

  def down
    # Revert: add back invoice_item_id
    add_reference :reminders, :invoice_item, foreign_key: true, null: true
    
    # Migrate data back
    execute <<-SQL.squish
      UPDATE reminders
      SET invoice_item_id = iw.invoice_item_id
      FROM item_warranties iw
      WHERE reminders.item_warranty_id = iw.id
    SQL
    
    remove_index :reminders, name: "idx_unique_reminders_warranty"
    remove_index :reminders, name: "index_reminders_on_item_warranty_id"
    
    change_column_null :reminders, :item_warranty_id, true
    remove_reference :reminders, :item_warranty
    
    # Restore old indexes
    add_index :reminders, [:invoice_item_id, :reminder_type, :remind_at], 
              unique: true, name: "index_reminders_unique_per_item_type_time"
  end
end
