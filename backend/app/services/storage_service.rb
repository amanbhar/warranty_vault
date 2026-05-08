# Storage Service - Handles file storage for development (local) and production (S3)
# Development: Stores files in public/uploads/invoices/
# Production: Uses AWS S3 via ActiveStorage
class StorageService
  class StorageError < StandardError; end

  DEVELOPMENT_UPLOAD_DIR = Rails.root.join("public/uploads/invoices")

  def self.service
    @service ||= new
  end

  # Save invoice file to appropriate storage
  # Returns file URL/path
  def save_invoice_file(invoice, uploaded_file)
    if Rails.env.production?
      save_to_s3(invoice, uploaded_file)
    else
      save_to_local(invoice, uploaded_file)
    end
  end

  # Get file URL for display
  def file_url(invoice)
    return nil unless invoice.file.attached?

    if Rails.env.production?
      # S3 returns public URL
      invoice.file.blob.service.url_for(invoice.file.blob)
    else
      # Local storage - return relative path
      invoice.file_url
    end
  end

  # Download file content
  def download_file(invoice)
    return nil unless invoice.file.attached?
    invoice.file.blob.download
  end

  # Delete file from storage
  def delete_file(invoice)
    # Clean up local file if exists
    if invoice.file_url.present? && !Rails.env.production?
      local_path = Rails.root.join("public", invoice.file_url.gsub(/^\//, ""))
      File.delete(local_path) if File.exist?(local_path)
    end

    # Purge ActiveStorage attachment
    invoice.file.purge if invoice.file.attached?
  end

  private

  # Save to local filesystem (development)
  def save_to_local(invoice, uploaded_file)
    # Ensure directory exists
    FileUtils.mkdir_p(DEVELOPMENT_UPLOAD_DIR)

    # Generate unique filename
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    original_name = uploaded_file.original_filename || "invoice"
    safe_name = original_name.gsub(/[^a-zA-Z0-9._-]/, "_")
    filename = "#{invoice.id}_#{timestamp}_#{safe_name}"

    # Full path
    file_path = DEVELOPMENT_UPLOAD_DIR.join(filename)

    # Write file
    File.binwrite(file_path, uploaded_file.read)

    # Store relative URL in invoice
    relative_url = "/uploads/invoices/#{filename}"
    invoice.update_column(:file_url, relative_url)

    # Also attach to ActiveStorage for consistency
    invoice.file.attach(
      io: File.open(file_path),
      filename: original_name,
      content_type: uploaded_file.content_type
    )

    relative_url
  end

  # Save to S3 (production)
  def save_to_s3(invoice, uploaded_file)
    # ActiveStorage handles S3 upload automatically
    invoice.file.attach(uploaded_file)

    # Return blob key for reference
    invoice.file.blob.key
  end

  # Ensure upload directory exists
  def ensure_local_directory
    FileUtils.mkdir_p(DEVELOPMENT_UPLOAD_DIR) unless Dir.exist?(DEVELOPMENT_UPLOAD_DIR)
  end
end
