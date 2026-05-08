# Service to handle file storage with environment-aware configuration
# Uses local storage in development, AWS S3 in production
class FileStorageService
  class StorageError < StandardError; end

  SUPPORTED_FORMATS = %w[application/pdf image/jpeg image/png image/jpg].freeze
  MAX_FILE_SIZE = 10.megabytes

  def self.upload(invoice, file)
    new(invoice, file).upload
  end

  def self.download_url(invoice)
    new(invoice, nil).download_url
  end

  def initialize(invoice, file = nil)
    @invoice = invoice
    @file = file
  end

  def upload
    raise StorageError, "No file provided" unless @file
    raise StorageError, "Unsupported file type: #{@file.content_type}" unless supported_format?
    raise StorageError, "File too large: #{@file.size} bytes (max: #{MAX_FILE_SIZE})" if file_too_large?

    Rails.logger.info "[FileStorageService] Uploading file for invoice #{@invoice.id}"

    # Attach file using Active Storage
    @invoice.file.attach(@file)

    # Store file URL for easy access
    @invoice.update_column(:file_url, generate_file_url)

    Rails.logger.info "[FileStorageService] File uploaded successfully for invoice #{@invoice.id}"

    {
      success: true,
      file_url: @invoice.file_url,
      filename: @file.original_filename,
      content_type: @file.content_type,
      size: @file.size
    }
  rescue => e
    Rails.logger.error "[FileStorageService] Upload failed: #{e.message}"
    raise StorageError, "Failed to upload file: #{e.message}"
  end

  def download_url
    return nil unless @invoice.file.attached?

    if Rails.env.production?
      # Generate presigned URL for S3
      @invoice.file.url(expires_in: 1.hour)
    else
      # Local storage URL
      Rails.application.routes.url_helpers.rails_blob_url(@invoice.file, only_path: true)
    end
  end

  def self.cleanup_old_files
    # Clean up files from invoices older than 30 days with no associated invoice
    old_date = 30.days.ago

    ActiveStorage::Blob.where(created_at: ..old_date).find_each do |blob|
      # Check if blob is still attached to any invoice
      if blob.attachments.empty?
        Rails.logger.info "[FileStorageService] Cleaning up unused blob: #{blob.id}"
        blob.purge
      end
    end
  end

  private

  def supported_format?
    SUPPORTED_FORMATS.include?(@file.content_type)
  end

  def file_too_large?
    @file.size > MAX_FILE_SIZE
  end

  def generate_file_url
    if Rails.env.production?
      # In production, file will be stored on S3
      "https://#{ENV.fetch('AWS_S3_BUCKET')}.s3.#{ENV.fetch('AWS_REGION')}.amazonaws.com/invoices/#{@invoice.id}/#{SecureRandom.hex(8)}-#{@file.original_filename}"
    else
      # In development, use local storage
      "/uploads/invoices/#{@invoice.id}/#{@file.original_filename}"
    end
  end
end
