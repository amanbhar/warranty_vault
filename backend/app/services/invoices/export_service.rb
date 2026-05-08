# frozen_string_literal: true

require "zip"

module Invoices
  class ExportService
    def self.call(user)
      new(user).call
    end

    def initialize(user)
      @user = user
      @zip_file = Tempfile.new([ "invoices", ".zip" ])
    end

    def call
      Zip::File.open(@zip_file.path, create: true) do |zipfile|
        @user.invoices.each do |invoice|
          add_invoice_to_zip(zipfile, invoice)
        end
      end

      @zip_file
    rescue => e
      Rails.logger.error "[ExportService] Error creating ZIP: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    ensure
      # Don't delete yet — controller will send it
    end

    private

    def add_invoice_to_zip(zipfile, invoice)
      # Get the attached PDF
      pdf_blob = invoice.file_attachment&.blob
      return unless pdf_blob

      # Generate filename: product_name_invoice_number.pdf
      filename = generate_filename(invoice)

      # Get the actual file path from Active Storage
      file_path = pdf_blob.service.path_for(pdf_blob.key)

      # Add to ZIP using rubyzip 3.x syntax
      zipfile.add(filename, file_path)

      Rails.logger.info "[ExportService] Added #{filename} to ZIP"
    rescue => e
      Rails.logger.error "[ExportService] Failed to add #{invoice.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Continue with next invoice even if one fails
    end

    def generate_filename(invoice)
      # Get product name from first item or invoice
      product_name = if invoice.invoice_items.present?
                       invoice.invoice_items.first.product_name
      else
                       invoice.product_name
      end

      product_name = product_name&.parameterize || "product"
      invoice_number = invoice.invoice_number&.parameterize || invoice.id

      # Ensure filename is safe and unique
      filename = "#{product_name}_#{invoice_number}.pdf"
      filename = filename.gsub(/[^a-zA-Z0-9._-]/, "_")

      filename
    end
  end
end
