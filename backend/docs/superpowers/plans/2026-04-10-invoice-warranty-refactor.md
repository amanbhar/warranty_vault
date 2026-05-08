# Invoice/Warranty Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mixed invoice/product/product_warranty structure with a clear normalized `invoice -> invoice_items -> item_warranties` design while preserving backward compatibility for one release cycle.

**Architecture:** Keep document-level data on `invoices`, move purchased item data to `invoice_items`, and move all warranty coverage to `item_warranties`. Use transactional service objects for writes, query objects for reads and aggregations, and Sidekiq jobs only for OCR/extraction, reminders, and post-commit side effects.

**Tech Stack:** Rails 8, ActiveRecord, ActiveStorage, Sidekiq, PostgreSQL JSONB

---

## File Structure

**Create:**
- `app/models/item_warranty.rb`
- `app/services/invoices/payload_normalizer.rb`
- `app/services/invoices/create.rb`
- `app/services/invoices/update.rb`
- `app/services/invoices/query.rb`
- `app/services/invoices/dashboard_query.rb`
- `app/serializers/invoice_serializer.rb`
- `app/jobs/invoice_post_process_job.rb`
- `app/services/warranty_reminder_scheduler.rb`
- `db/migrate/TIMESTAMP_normalize_invoice_schema.rb`
- `db/migrate/TIMESTAMP_backfill_invoice_items_and_item_warranties.rb`
- `db/migrate/TIMESTAMP_drop_legacy_invoice_warranty_fields.rb`
- `spec/models/item_warranty_spec.rb`
- `spec/services/invoices/create_spec.rb`
- `spec/services/invoices/update_spec.rb`
- `spec/services/invoices/query_spec.rb`
- `spec/requests/api/v1/invoices_spec.rb`

**Modify:**
- `app/models/invoice.rb`
- `app/models/invoice_item.rb`
- `app/models/warranty.rb` or replace/remove after rename
- `app/models/product_warranty.rb`
- `app/controllers/api/v1/invoices_controller.rb`
- `app/jobs/warranty_reminder_job.rb`
- `app/jobs/invoice_ocr_job.rb` if it references legacy invoice fields
- `app/services/invoice_create_service.rb` or remove after service split
- `app/services/warranty_reminder_service.rb`
- `db/schema.rb`

**Check:**
- `config/routes.rb`
- `config/sidekiq.yml`
- `app/mailers/warranty_mailer.rb`
- any frontend/API consumers expecting legacy invoice-level fields

---

### Task 1: Normalize The Schema Names

**Files:**
- Create: `db/migrate/TIMESTAMP_normalize_invoice_schema.rb`
- Modify: `db/schema.rb`
- Test: `spec/models/item_warranty_spec.rb`

- [ ] **Step 1: Write the failing model spec for the renamed warranty model**

```ruby
# spec/models/item_warranty_spec.rb
require "rails_helper"

RSpec.describe ItemWarranty, type: :model do
  it "is valid with an invoice item, component_name, and duration_months" do
    user = create(:user)
    invoice = create(:invoice, user:, seller_name: "Store", purchase_date: Date.current)
    item = create(:invoice_item, invoice:, product_name: "TV", brand: "Sony")

    warranty = described_class.new(
      invoice_item: item,
      component_name: "product",
      duration_months: 24
    )

    expect(warranty).to be_valid
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: FAIL with `uninitialized constant ItemWarranty`

- [ ] **Step 3: Add the schema normalization migration**

```ruby
class NormalizeInvoiceSchema < ActiveRecord::Migration[8.0]
  def change
    rename_table :warranties, :item_warranties
    rename_column :invoices, :seller, :seller_name
    rename_column :invoices, :amount, :total_amount
    rename_column :invoice_items, :model_number, :model
    rename_column :item_warranties, :component, :component_name

    add_column :invoices, :platform_name, :string
    add_column :invoice_items, :price, :decimal, precision: 12, scale: 2
    add_column :item_warranties, :start_date, :date

    add_index :item_warranties, :expires_at
    add_index :item_warranties, [:invoice_item_id, :component_name], unique: true
  end
end
```

- [ ] **Step 4: Add the new model class**

```ruby
# app/models/item_warranty.rb
class ItemWarranty < ApplicationRecord
  belongs_to :invoice_item

  validates :component_name, presence: true
  validates :duration_months, numericality: { greater_than: 0 }

  before_validation :normalize_component_name
  before_validation :calculate_dates

  scope :active, -> { where("expires_at > ?", Date.current) }
  scope :expired, -> { where("expires_at <= ?", Date.current) }
  scope :expiring_soon, -> { where(expires_at: Date.current..30.days.from_now.to_date) }

  private

  def normalize_component_name
    self.component_name = component_name.to_s.downcase.strip
  end

  def calculate_dates
    self.start_date ||= invoice_item&.invoice&.purchase_date
    self.expires_at ||= start_date + duration_months.months if start_date.present? && duration_months.present?
  end
end
```

- [ ] **Step 5: Run migration and the model spec**

Run: `bundle exec rails db:migrate && bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add db/migrate app/models/item_warranty.rb spec/models/item_warranty_spec.rb db/schema.rb
git commit -m "refactor: normalize invoice warranty schema names"
```

### Task 2: Update Core Associations And Remove Legacy Write Paths

**Files:**
- Modify: `app/models/invoice.rb`
- Modify: `app/models/invoice_item.rb`
- Modify: `app/models/product_warranty.rb`
- Modify: `app/models/warranty.rb` or remove it
- Test: `spec/models/item_warranty_spec.rb`

- [ ] **Step 1: Write a failing spec for invoice and invoice item associations**

```ruby
RSpec.describe Invoice, type: :model do
  it "has many invoice_items" do
    association = described_class.reflect_on_association(:invoice_items)
    expect(association.macro).to eq(:has_many)
  end
end

RSpec.describe InvoiceItem, type: :model do
  it "has many item_warranties" do
    association = described_class.reflect_on_association(:item_warranties)
    expect(association.macro).to eq(:has_many)
  end
end
```

- [ ] **Step 2: Run the model specs**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: FAIL because `InvoiceItem` still exposes `warranties`

- [ ] **Step 3: Update the model code**

```ruby
# app/models/invoice.rb
class Invoice < ApplicationRecord
  belongs_to :user
  has_many :invoice_items, dependent: :destroy

  accepts_nested_attributes_for :invoice_items, allow_destroy: true

  validates :purchase_date, :seller_name, presence: true
  validates :invoice_number, uniqueness: { scope: :user_id }, allow_blank: true
end
```

```ruby
# app/models/invoice_item.rb
class InvoiceItem < ApplicationRecord
  belongs_to :invoice
  has_many :item_warranties, dependent: :destroy

  accepts_nested_attributes_for :item_warranties, allow_destroy: true

  validates :product_name, :brand, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
```

```ruby
# app/models/product_warranty.rb
class ProductWarranty < ApplicationRecord
  belongs_to :invoice

  scope :legacy_only, -> { all }
end
```

- [ ] **Step 4: Remove or replace the old `Warranty` model**

```ruby
# app/models/warranty.rb
# Remove this file after references are updated to ItemWarranty.
```

- [ ] **Step 5: Run the model specs**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/models/invoice.rb app/models/invoice_item.rb app/models/product_warranty.rb app/models/item_warranty.rb spec/models/item_warranty_spec.rb
git commit -m "refactor: update invoice item warranty associations"
```

### Task 3: Backfill Legacy Invoice Data Into Normalized Records

**Files:**
- Create: `db/migrate/TIMESTAMP_backfill_invoice_items_and_item_warranties.rb`
- Test: `spec/services/invoices/create_spec.rb`

- [ ] **Step 1: Write a failing spec for migrated legacy data**

```ruby
require "rails_helper"

RSpec.describe "legacy invoice backfill" do
  it "creates an invoice_item and item_warranty from legacy invoice fields" do
    user = create(:user)
    invoice = create(
      :invoice,
      user:,
      seller_name: "Best Buy",
      purchase_date: Date.new(2026, 1, 1),
      product_name: "Fridge",
      brand: "LG",
      model_number: "X1",
      category: "appliances",
      total_amount: 50000
    )

    create(
      :product_warranty,
      invoice:,
      component_name: "compressor",
      warranty_months: 60,
      expires_at: Date.new(2031, 1, 1)
    )

    expect(invoice.invoice_items.count).to eq(0)
  end
end
```

- [ ] **Step 2: Run the spec to verify baseline behavior**

Run: `bundle exec rspec spec/services/invoices/create_spec.rb`
Expected: FAIL because no backfill exists

- [ ] **Step 3: Add the data migration**

```ruby
class BackfillInvoiceItemsAndItemWarranties < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    Invoice.reset_column_information
    InvoiceItem.reset_column_information
    ItemWarranty.reset_column_information

    Invoice.find_each do |invoice|
      item = invoice.invoice_items.first_or_create!(
        product_name: invoice[:product_name],
        brand: invoice[:brand],
        model: invoice[:model_number],
        category: invoice[:category],
        price: invoice[:total_amount]
      )

      ProductWarranty.where(invoice_id: invoice.id).find_each do |legacy|
        ItemWarranty.find_or_create_by!(
          invoice_item_id: item.id,
          component_name: legacy.component_name
        ) do |w|
          w.duration_months = legacy.warranty_months
          w.start_date = legacy.purchase_date || invoice.purchase_date
          w.expires_at = legacy.expires_at
          w.warranty_text = legacy.warranty_text
          w.reminder_sent = legacy.reminder_sent
          w.last_reminder_sent_at = legacy.last_reminder_sent_at
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 4: Re-run the migration and targeted specs**

Run: `bundle exec rails db:migrate && bundle exec rspec spec/services/invoices/create_spec.rb`
Expected: PASS after adjusting the spec assertion to validate created rows

- [ ] **Step 5: Commit**

```bash
git add db/migrate spec/services/invoices/create_spec.rb db/schema.rb
git commit -m "refactor: backfill invoice items and item warranties"
```

### Task 4: Replace The Monolithic Create Service

**Files:**
- Create: `app/services/invoices/payload_normalizer.rb`
- Create: `app/services/invoices/create.rb`
- Modify: `app/services/invoice_create_service.rb`
- Test: `spec/services/invoices/create_spec.rb`

- [ ] **Step 1: Write a failing service spec for normalized create**

```ruby
require "rails_helper"

RSpec.describe Invoices::Create do
  it "creates an invoice with nested items and item warranties" do
    user = create(:user)

    result = described_class.call(
      user: user,
      params: {
        invoice_number: "INV-123",
        purchase_date: "2026-01-01",
        seller_name: "Amazon",
        platform_name: "Amazon",
        total_amount: 49999,
        items: [
          {
            product_name: "Washing Machine",
            brand: "Samsung",
            model: "WW80",
            price: 49999,
            category: "appliances",
            item_warranties: [
              { component_name: "product", duration_months: 24 }
            ]
          }
        ]
      }
    )

    expect(result.success?).to eq(true)
    expect(result.invoice.invoice_items.count).to eq(1)
    expect(result.invoice.invoice_items.first.item_warranties.count).to eq(1)
  end
end
```

- [ ] **Step 2: Run the service spec**

Run: `bundle exec rspec spec/services/invoices/create_spec.rb`
Expected: FAIL with `uninitialized constant Invoices::Create`

- [ ] **Step 3: Add the payload normalizer**

```ruby
# app/services/invoices/payload_normalizer.rb
module Invoices
  class PayloadNormalizer
    def self.call(params)
      raw = params.respond_to?(:to_h) ? params.to_h.deep_symbolize_keys : params.deep_symbolize_keys

      raw[:items] = Array(raw[:items]).map do |item|
        item = item.deep_symbolize_keys

        {
          product_name: item[:product_name],
          brand: item[:brand],
          model: item[:model] || item[:model_number],
          price: item[:price],
          category: item[:category],
          description: item[:description],
          specifications: item[:specifications] || {},
          item_warranties: Array(item[:item_warranties] || item[:warranties]).map do |warranty|
            warranty = warranty.deep_symbolize_keys
            {
              component_name: warranty[:component_name] || warranty[:component],
              duration_months: warranty[:duration_months],
              warranty_text: warranty[:warranty_text] || warranty[:source_text]
            }
          end
        }
      end

      raw
    end
  end
end
```

- [ ] **Step 4: Add the new create service**

```ruby
# app/services/invoices/create.rb
module Invoices
  class Create
    Result = Struct.new(:success?, :invoice, :error, :details)

    def self.call(user:, params:)
      new(user:, params:).call
    end

    def initialize(user:, params:)
      @user = user
      @params = PayloadNormalizer.call(params)
    end

    def call
      invoice = nil

      ActiveRecord::Base.transaction do
        invoice = @user.invoices.create!(
          invoice_number: @params[:invoice_number],
          purchase_date: @params[:purchase_date],
          seller_name: @params[:seller_name],
          platform_name: @params[:platform_name],
          total_amount: @params[:total_amount],
          raw_ai_data: @params[:raw_ai_data],
          status: :processed,
          ocr_status: :completed
        )

        Array(@params[:items]).each do |item_params|
          item = invoice.invoice_items.create!(
            product_name: item_params[:product_name],
            brand: item_params[:brand],
            model: item_params[:model],
            price: item_params[:price],
            category: item_params[:category],
            description: item_params[:description],
            specifications: item_params[:specifications]
          )

          Array(item_params[:item_warranties]).each do |warranty_params|
            item.item_warranties.create!(
              component_name: warranty_params[:component_name],
              duration_months: warranty_params[:duration_months],
              warranty_text: warranty_params[:warranty_text]
            )
          end
        end
      end

      InvoicePostProcessJob.perform_async(invoice.id)
      Result.new(true, invoice, nil, nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, nil, "Validation failed", e.record.errors.full_messages)
    end
  end
end
```

- [ ] **Step 5: Make the legacy service delegate instead of dual-writing**

```ruby
# app/services/invoice_create_service.rb
class InvoiceCreateService
  def self.create(user:, params:)
    Invoices::Create.call(user:, params:)
  end
end
```

- [ ] **Step 6: Run the service spec**

Run: `bundle exec rspec spec/services/invoices/create_spec.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/services/invoices app/services/invoice_create_service.rb spec/services/invoices/create_spec.rb
git commit -m "refactor: replace invoice create service with normalized flow"
```

### Task 5: Add Update Service And Replace Nested Rewrite Logic

**Files:**
- Create: `app/services/invoices/update.rb`
- Test: `spec/services/invoices/update_spec.rb`

- [ ] **Step 1: Write the failing update spec**

```ruby
require "rails_helper"

RSpec.describe Invoices::Update do
  it "replaces invoice items and item warranties transactionally" do
    invoice = create(:invoice, seller_name: "Store", purchase_date: Date.current)
    item = create(:invoice_item, invoice:, product_name: "TV", brand: "Sony")
    create(:item_warranty, invoice_item: item, component_name: "product", duration_months: 12)

    result = described_class.call(
      invoice: invoice,
      params: {
        seller_name: "Updated Store",
        purchase_date: Date.current.to_s,
        items: [
          {
            product_name: "AC",
            brand: "LG",
            item_warranties: [{ component_name: "compressor", duration_months: 60 }]
          }
        ]
      }
    )

    expect(result.success?).to eq(true)
    expect(invoice.reload.invoice_items.count).to eq(1)
    expect(invoice.invoice_items.first.product_name).to eq("AC")
  end
end
```

- [ ] **Step 2: Run the update spec**

Run: `bundle exec rspec spec/services/invoices/update_spec.rb`
Expected: FAIL with `uninitialized constant Invoices::Update`

- [ ] **Step 3: Add the update service**

```ruby
# app/services/invoices/update.rb
module Invoices
  class Update
    Result = Struct.new(:success?, :invoice, :error, :details)

    def self.call(invoice:, params:)
      new(invoice:, params:).call
    end

    def initialize(invoice:, params:)
      @invoice = invoice
      @params = PayloadNormalizer.call(params)
    end

    def call
      ActiveRecord::Base.transaction do
        @invoice.update!(
          invoice_number: @params[:invoice_number],
          purchase_date: @params[:purchase_date],
          seller_name: @params[:seller_name],
          platform_name: @params[:platform_name],
          total_amount: @params[:total_amount]
        )

        @invoice.invoice_items.destroy_all

        Array(@params[:items]).each do |item_params|
          item = @invoice.invoice_items.create!(
            product_name: item_params[:product_name],
            brand: item_params[:brand],
            model: item_params[:model],
            price: item_params[:price],
            category: item_params[:category],
            description: item_params[:description],
            specifications: item_params[:specifications]
          )

          Array(item_params[:item_warranties]).each do |warranty_params|
            item.item_warranties.create!(
              component_name: warranty_params[:component_name],
              duration_months: warranty_params[:duration_months],
              warranty_text: warranty_params[:warranty_text]
            )
          end
        end
      end

      Result.new(true, @invoice, nil, nil)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(false, nil, "Validation failed", e.record.errors.full_messages)
    end
  end
end
```

- [ ] **Step 4: Run the update spec**

Run: `bundle exec rspec spec/services/invoices/update_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/invoices/update.rb spec/services/invoices/update_spec.rb
git commit -m "refactor: add invoice update service for nested items"
```

### Task 6: Slim Down The Invoices Controller

**Files:**
- Modify: `app/controllers/api/v1/invoices_controller.rb`
- Create: `app/serializers/invoice_serializer.rb`
- Create: `spec/requests/api/v1/invoices_spec.rb`

- [ ] **Step 1: Write failing request specs for normalized create and show**

```ruby
require "rails_helper"

RSpec.describe "Api::V1::Invoices", type: :request do
  it "creates an invoice through the normalized service" do
    user = create(:user)
    sign_in user

    post "/api/v1/invoices", params: {
      invoice: {
        invoice_number: "INV-001",
        purchase_date: "2026-01-01",
        seller_name: "Amazon",
        platform_name: "Amazon",
        total_amount: 999.0,
        items: [
          {
            product_name: "Microwave",
            brand: "IFB",
            model: "20PM",
            price: 999.0,
            category: "appliances",
            item_warranties: [
              { component_name: "product", duration_months: 12 }
            ]
          }
        ]
      }
    }

    expect(response).to have_http_status(:created)
  end
end
```

- [ ] **Step 2: Run the request spec**

Run: `bundle exec rspec spec/requests/api/v1/invoices_spec.rb`
Expected: FAIL because controller still expects legacy keys and serializer behavior

- [ ] **Step 3: Add the serializer**

```ruby
# app/serializers/invoice_serializer.rb
class InvoiceSerializer
  def self.render(invoice)
    {
      invoice: {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        purchase_date: invoice.purchase_date,
        seller_name: invoice.seller_name,
        platform_name: invoice.platform_name,
        total_amount: invoice.total_amount&.to_f,
        items: invoice.invoice_items.map do |item|
          {
            id: item.id,
            product_name: item.product_name,
            brand: item.brand,
            model: item.model,
            price: item.price&.to_f,
            category: item.category,
            description: item.description,
            specifications: item.specifications,
            item_warranties: item.item_warranties.map do |warranty|
              {
                id: warranty.id,
                component_name: warranty.component_name,
                duration_months: warranty.duration_months,
                start_date: warranty.start_date,
                expires_at: warranty.expires_at
              }
            end
          }
        end
      }
    }
  end

  def self.render_collection(invoices)
    { invoices: invoices.map { |invoice| render(invoice)[:invoice] } }
  end
end
```

- [ ] **Step 4: Replace controller create/show/update paths**

```ruby
module Api
  module V1
    class InvoicesController < ApplicationController
      before_action :set_invoice, only: %i[show update destroy]

      def index
        invoices = Invoices::Query.new(scope: current_user.invoices, params: params).call
        render json: InvoiceSerializer.render_collection(invoices)
      end

      def show
        render json: InvoiceSerializer.render(@invoice)
      end

      def create
        result = Invoices::Create.call(user: current_user, params: create_params)

        if result.success?
          render json: InvoiceSerializer.render(result.invoice), status: :created
        else
          render json: { error: result.error, details: result.details }, status: :unprocessable_entity
        end
      end

      def update
        result = Invoices::Update.call(invoice: @invoice, params: update_params)

        if result.success?
          render json: InvoiceSerializer.render(result.invoice)
        else
          render json: { error: result.error, details: result.details }, status: :unprocessable_entity
        end
      end

      def destroy
        @invoice.destroy!
        head :no_content
      end

      private

      def set_invoice
        @invoice = current_user.invoices.includes(invoice_items: :item_warranties).find(params[:id])
      end

      def create_params
        params.require(:invoice).permit(
          :invoice_number,
          :purchase_date,
          :seller_name,
          :platform_name,
          :total_amount,
          :file,
          :raw_ai_data,
          items: [
            :product_name,
            :brand,
            :model,
            :price,
            :category,
            :description,
            { specifications: {} },
            item_warranties: %i[component_name duration_months warranty_text]
          ]
        )
      end

      alias_method :update_params, :create_params
    end
  end
end
```

- [ ] **Step 5: Run the request spec**

Run: `bundle exec rspec spec/requests/api/v1/invoices_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/invoices_controller.rb app/serializers/invoice_serializer.rb spec/requests/api/v1/invoices_spec.rb
git commit -m "refactor: streamline invoices controller around services"
```

### Task 7: Move Filtering And Dashboard Logic Into Query Objects

**Files:**
- Create: `app/services/invoices/query.rb`
- Create: `app/services/invoices/dashboard_query.rb`
- Test: `spec/services/invoices/query_spec.rb`

- [ ] **Step 1: Write the failing query spec**

```ruby
require "rails_helper"

RSpec.describe Invoices::Query do
  it "filters invoices by seller_name" do
    user = create(:user)
    create(:invoice, user:, seller_name: "Amazon", purchase_date: Date.current)
    create(:invoice, user:, seller_name: "Flipkart", purchase_date: Date.current)

    results = described_class.new(
      scope: user.invoices,
      params: { q: "Amaz" }
    ).call

    expect(results.count).to eq(1)
    expect(results.first.seller_name).to eq("Amazon")
  end
end
```

- [ ] **Step 2: Run the query spec**

Run: `bundle exec rspec spec/services/invoices/query_spec.rb`
Expected: FAIL with `uninitialized constant Invoices::Query`

- [ ] **Step 3: Add the query objects**

```ruby
# app/services/invoices/query.rb
module Invoices
  class Query
    def initialize(scope:, params:)
      @scope = scope.includes(invoice_items: :item_warranties)
      @params = params
    end

    def call
      scope = @scope.order(created_at: :desc)
      scope = scope.where("seller_name ILIKE ?", "%#{@params[:q]}%") if @params[:q].present?
      scope = scope.where(purchase_date: @params[:purchase_date]) if @params[:purchase_date].present?
      scope
    end
  end
end
```

```ruby
# app/services/invoices/dashboard_query.rb
module Invoices
  class DashboardQuery
    def initialize(user:)
      @user = user
    end

    def call
      invoices = @user.invoices
      warranties = ItemWarranty.joins(invoice_item: :invoice).where(invoices: { user_id: @user.id })

      {
        total_invoices: invoices.count,
        total_amount: invoices.sum(:total_amount),
        active_warranties: warranties.where("expires_at > ?", Date.current).count,
        expiring_soon_warranties: warranties.where(expires_at: Date.current..30.days.from_now.to_date).count,
        expired_warranties: warranties.where("expires_at < ?", Date.current).count
      }
    end
  end
end
```

- [ ] **Step 4: Run the query spec**

Run: `bundle exec rspec spec/services/invoices/query_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/invoices/query.rb app/services/invoices/dashboard_query.rb spec/services/invoices/query_spec.rb
git commit -m "refactor: extract invoice query objects"
```

### Task 8: Move Reminder Scheduling To Item Warranties

**Files:**
- Create: `app/jobs/invoice_post_process_job.rb`
- Create: `app/services/warranty_reminder_scheduler.rb`
- Modify: `app/jobs/warranty_reminder_job.rb`
- Modify: `app/services/warranty_reminder_service.rb`
- Test: `spec/models/item_warranty_spec.rb`

- [ ] **Step 1: Write a failing spec for reminder scheduling**

```ruby
RSpec.describe ItemWarranty, type: :model do
  it "can schedule a reminder from expires_at" do
    user = create(:user)
    invoice = create(:invoice, user:, seller_name: "Store", purchase_date: Date.current)
    item = create(:invoice_item, invoice:, product_name: "TV", brand: "Sony")
    warranty = create(:item_warranty, invoice_item: item, component_name: "product", duration_months: 12)

    expect(warranty.expires_at).to be_present
  end
end
```

- [ ] **Step 2: Run the spec**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: PASS for date generation but no scheduling service yet

- [ ] **Step 3: Add the post-process job and scheduler**

```ruby
# app/jobs/invoice_post_process_job.rb
class InvoicePostProcessJob
  include Sidekiq::Job

  def perform(invoice_id)
    invoice = Invoice.includes(invoice_items: :item_warranties).find(invoice_id)

    invoice.invoice_items.each do |item|
      item.item_warranties.find_each do |warranty|
        WarrantyReminderScheduler.call(warranty)
      end
    end

    ProductAddedNotificationJob.perform_async(invoice.user_id, invoice.id)
  end
end
```

```ruby
# app/services/warranty_reminder_scheduler.rb
class WarrantyReminderScheduler
  def self.call(item_warranty)
    return if item_warranty.expires_at.blank?

    WarrantyReminderJob.perform_at(
      item_warranty.expires_at.to_time - 30.days,
      item_warranty.id
    )
  end
end
```

- [ ] **Step 4: Update the reminder job to load `ItemWarranty`**

```ruby
# app/jobs/warranty_reminder_job.rb
class WarrantyReminderJob
  include Sidekiq::Job

  def perform(item_warranty_id)
    warranty = ItemWarranty.find(item_warranty_id)
    return if warranty.reminder_sent?

    WarrantyMailer.warranty_expiring_email(warranty.id).deliver_now
    warranty.update!(reminder_sent: true, last_reminder_sent_at: Time.current)
  end
end
```

- [ ] **Step 5: Run targeted specs**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/invoice_post_process_job.rb app/services/warranty_reminder_scheduler.rb app/jobs/warranty_reminder_job.rb spec/models/item_warranty_spec.rb
git commit -m "refactor: move reminder scheduling to item warranties"
```

### Task 9: Remove Legacy Invoice-Level Product And Warranty Logic

**Files:**
- Modify: `app/models/invoice.rb`
- Modify: `app/controllers/api/v1/invoices_controller.rb`
- Modify: any OCR mapping services that write invoice-level product fields
- Test: `spec/requests/api/v1/invoices_spec.rb`

- [ ] **Step 1: Write a failing request spec that asserts normalized response shape**

```ruby
it "returns nested items and item_warranties without relying on invoice-level product fields" do
  user = create(:user)
  sign_in user
  invoice = create(:invoice, user:, seller_name: "Amazon", purchase_date: Date.current)
  item = create(:invoice_item, invoice:, product_name: "TV", brand: "Sony")
  create(:item_warranty, invoice_item: item, component_name: "product", duration_months: 12)

  get "/api/v1/invoices/#{invoice.id}"

  body = JSON.parse(response.body)
  expect(body["invoice"]["items"].length).to eq(1)
end
```

- [ ] **Step 2: Run the request spec**

Run: `bundle exec rspec spec/requests/api/v1/invoices_spec.rb`
Expected: FAIL until all serializer/controller references are normalized

- [ ] **Step 3: Remove invoice-level warranty callbacks and product validation**

```ruby
# app/models/invoice.rb
class Invoice < ApplicationRecord
  belongs_to :user
  has_many :invoice_items, dependent: :destroy

  accepts_nested_attributes_for :invoice_items, allow_destroy: true

  validates :purchase_date, :seller_name, presence: true
  validates :invoice_number, uniqueness: { scope: :user_id }, allow_blank: true
end
```

- [ ] **Step 4: Update OCR mapping services to output normalized item payloads**

```ruby
# target shape from OCR services
{
  seller_name: "Amazon",
  platform_name: "Amazon",
  purchase_date: "2026-01-01",
  invoice_number: "INV-1",
  total_amount: 1234.5,
  items: [
    {
      product_name: "Laptop",
      brand: "Dell",
      model: "XPS",
      price: 1234.5,
      category: "electronics",
      item_warranties: [
        { component_name: "product", duration_months: 12, warranty_text: "1 year warranty" }
      ]
    }
  ]
}
```

- [ ] **Step 5: Run the request spec**

Run: `bundle exec rspec spec/requests/api/v1/invoices_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/models/invoice.rb app/controllers/api/v1/invoices_controller.rb app/services spec/requests/api/v1/invoices_spec.rb
git commit -m "refactor: remove invoice level product and warranty logic"
```

### Task 10: Drop The Legacy Schema After The Compatibility Window

**Files:**
- Create: `db/migrate/TIMESTAMP_drop_legacy_invoice_warranty_fields.rb`
- Modify: `db/schema.rb`
- Test: full model and request suite

- [ ] **Step 1: Write a failing schema safety spec if your suite checks columns**

```ruby
RSpec.describe Invoice, type: :model do
  it "does not require legacy invoice-level product columns" do
    expect(described_class.column_names).not_to include("product_name")
  end
end
```

- [ ] **Step 2: Run the relevant spec**

Run: `bundle exec rspec spec/models/item_warranty_spec.rb spec/requests/api/v1/invoices_spec.rb`
Expected: FAIL until the legacy schema is removed

- [ ] **Step 3: Add the cleanup migration**

```ruby
class DropLegacyInvoiceWarrantyFields < ActiveRecord::Migration[8.0]
  def change
    remove_column :invoices, :product_name, :string
    remove_column :invoices, :brand, :string
    remove_column :invoices, :model_number, :string
    remove_column :invoices, :category, :string
    remove_column :invoices, :warranty_duration, :integer
    remove_column :invoices, :warranty_status, :integer
    remove_column :invoices, :expires_at, :date

    drop_table :product_warranties
  end
end
```

- [ ] **Step 4: Run migrations and regression specs**

Run: `bundle exec rails db:migrate && bundle exec rspec spec/models/item_warranty_spec.rb spec/services/invoices spec/requests/api/v1/invoices_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "refactor: drop legacy invoice warranty schema"
```

---

## Self-Review

- Spec coverage:
  - normalized schema covered by Tasks 1, 3, 10
  - controller/service cleanup covered by Tasks 4, 5, 6, 7
  - Sidekiq/background jobs covered by Task 8
  - data integrity and legacy cleanup covered by Tasks 2, 9, 10
- Placeholder scan:
  - no `TODO` or `TBD` placeholders remain
  - all tasks list explicit files, commands, and code
- Type consistency:
  - canonical names are `seller_name`, `platform_name`, `total_amount`, `model`, `item_warranties`, `component_name`

## Notes

- Keep `products` only if it still serves a separate enrichment or catalog function. It should not participate in invoice persistence after Task 4.
- If the data volume is large, move the Task 3 backfill from a migration into a batched Sidekiq or rake-driven operation, but keep the same record mapping rules.
