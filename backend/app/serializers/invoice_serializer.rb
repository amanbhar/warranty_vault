# frozen_string_literal: true

class InvoiceSerializer
  # Serializes an Invoice record into a JSON-friendly hash.
  #
  # Usage:
  #   InvoiceSerializer.render(invoice)
  #   InvoiceSerializer.render_collection(invoices)
  def self.render(invoice, include_warranties: false)
    first_item = invoice.invoice_items.first
    data = {
      id: invoice.id,
      invoice_number: invoice.invoice_number,
      seller_name: invoice.seller_name,
      platform_name: invoice.platform_name,
      total_amount: invoice.total_amount&.to_f,
      purchase_date: invoice.purchase_date,
      product_name: first_item&.product_name,
      brand: first_item&.brand,
      model: first_item&.model,
      category: first_item&.category,
      status: invoice.status,
      ocr_status: invoice.ocr_status,
      ocr_error_message: invoice.ocr_error_message,
      invoice_status: invoice.overall_warranty_status,
      warranty_status: invoice.overall_warranty_status, # Keep for backward compatibility
      days_remaining: invoice.days_remaining,
      expires_at: invoice.expires_at,
      formatted_amount: invoice.formatted_amount,
      has_file: invoice.file.attached?,
      file_url: file_url(invoice),
      has_product_image: invoice.product_image.attached?,
      product_image_url: product_image_url(invoice),
      original_filename: invoice.original_filename,
      created_at: invoice.created_at,
      updated_at: invoice.updated_at
    }

    if include_warranties
      data[:items] = invoice.invoice_items.map { |item| serialize_item(item) }
    end

    data
  end

  def self.render_collection(invoices, include_warranties: false)
    invoices.map { |invoice| render(invoice, include_warranties: include_warranties) }
  end

  def self.serialize_item(item)
    {
      id: item.id,
      product_name: item.product_name,
      brand: item.brand,
      model: item.model,
      price: item.price&.to_f,
      category: item.category,
      description: item.description,
      specifications: item.specifications,
      item_status: item.status,
      nearest_expiry_date: item.nearest_expiry_date,
      warranties: item.item_warranties.map { |w| serialize_warranty(w) },
      reminders: item.reminders.order(:remind_at).map { |r| serialize_reminder(r) }
    }
  end

  def self.serialize_reminder(r)
    {
      id: r.id,
      item_warranty_id: r.item_warranty_id,
      remind_at: r.remind_at,
      reminder_type: r.reminder_type,
      sent: r.sent
    }
  end

  def self.serialize_warranty(w)
    {
      id: w.id,
      component: w.component_name,
      component_display: w.component_display_name,
      duration_months: w.duration_months,
      start_date: w.start_date,
      expires_at: w.expires_at,
      days_remaining: w.days_remaining,
      status: w.status
    }
  end

  def self.serialize_legacy_warranty(pw)
    {
      id: pw.id,
      component_name: pw.component_name,
      component_display: pw.component_display_name,
      warranty_months: pw.warranty_months,
      formatted_duration: pw.formatted_duration,
      expires_at: pw.expires_at,
      days_remaining: pw.days_remaining,
      status: pw.active? ? "active" : (pw.expired? ? "expired" : "expiring_soon"),
      reminder_sent: pw.reminder_sent
    }
  end

  def self.warranty_status(w)
    return "unknown" unless w.expires_at
    if w.active?
      "active"
    elsif w.expired?
      "expired"
    else
      "expiring_soon"
    end
  end

  def self.file_url(invoice)
    return nil unless invoice.file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(invoice.file, only_path: true)
  end

  def self.product_image_url(invoice)
    return nil unless invoice.product_image.attached?
    Rails.application.routes.url_helpers.rails_blob_url(invoice.product_image, only_path: true)
  end

  # 0 = expired, 1 = active/unknown, 2 = expiring_soon (matches Invoices::Create mapping)
  WARRANTY_STATUS_LABELS = { 0 => "expired", 1 => "active", 2 => "expiring_soon" }.freeze

  def self.warranty_status_label(value)
    return "unknown" if value.nil?
    WARRANTY_STATUS_LABELS.fetch(value, "active")
  end

  def self.api_host
    ENV.fetch("APP_URL", nil)
  end

  private_class_method :serialize_item, :serialize_warranty, :serialize_legacy_warranty,
                       :warranty_status, :file_url, :product_image_url, :warranty_status_label, :api_host
end
