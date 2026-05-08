# OCR Service using Google Cloud Vision API
# Extracts text from PDF, JPG, PNG files using Google's Vision API
class OcrService
  include Rails.application.routes.url_helpers

  class OcrError < StandardError; end

  SUPPORTED_FORMATS = %w[application/pdf image/jpeg image/png image/jpg].freeze

  def initialize(invoice)
    @invoice = invoice
    @file = invoice.file
  end

  # Main entry point - extract text and parse invoice data
  def process
    raise OcrError, "No file attached" unless @file.attached?
    raise OcrError, "Unsupported file type: #{@file.content_type}" unless supported_format?

    Rails.logger.info "[OcrService] Starting Google Vision OCR for invoice #{@invoice.id}"

    # Download file and extract text using Google Vision
    text = extract_text

    return { success: false, error: "No text extracted from file" } if text.blank?

    # Parse the extracted text for invoice fields
    parsed_data = InvoiceFieldParser.new(text).parse

    # Store raw OCR data
    @invoice.update_columns(
      ocr_data: parsed_data.merge(raw_text: text).to_json,
      ocr_status: :processing
    )

    # Update invoice with extracted data
    @invoice.update_from_ocr(parsed_data)

    # Mark as completed if we got valid data
    if @invoice.purchase_date.present? || @invoice.product_name.present?
      @invoice.ocr_status = :completed
    else
      @invoice.ocr_status = :failed
      @invoice.ocr_error_message = "OCR could not extract required fields (product_name or purchase_date)"
    end

    @invoice.save!(validate: false)

    Rails.logger.info "[OcrService] Google Vision OCR complete for invoice #{@invoice.id}"

    {
      success: @invoice.ocr_status == :completed,
      data: parsed_data,
      raw_text: text,
      error: @invoice.ocr_error_message
    }
  rescue Google::Cloud::PermissionDeniedError => e
    Rails.logger.error "[OcrService] Google Vision permission denied: #{e.message}"
    @invoice.mark_ocr_failed("Google Vision API permission denied. Check credentials.")
    { success: false, error: "Google Vision API permission denied" }
  rescue Google::Cloud::InvalidArgumentError => e
    Rails.logger.error "[OcrService] Google Vision invalid argument: #{e.message}"
    @invoice.mark_ocr_failed("Invalid file format for Google Vision API.")
    { success: false, error: "Invalid file format" }
  rescue => e
    Rails.logger.error "[OcrService] Error processing invoice #{@invoice.id}: #{e.message}"
    Rails.logger.error "[OcrService] #{e.class}: #{e.backtrace.first(5).join("\n")}"
    @invoice.mark_ocr_failed(e.message)
    { success: false, error: e.message }
  end

  private

  def supported_format?
    SUPPORTED_FORMATS.include?(@file.content_type)
  end

  # Extract text from file using Google Cloud Vision
  def extract_text
    case @file.content_type
    when "application/pdf"
      extract_from_pdf
    when "image/jpeg", "image/png", "image/jpg"
      extract_from_image
    else
      raise OcrError, "Unsupported file type: #{@file.content_type}"
    end
  end

  # Extract text from PDF using Google Vision
  def extract_from_pdf
    file_path = download_file

    begin
      # Check if Google credentials are available
      if google_credentials_available?
        # Google Vision can process PDFs directly with async batch API
        # For smaller PDFs, we use synchronous detection
        vision = Google::Cloud::Vision.new(
          project_id: ENV.fetch("GOOGLE_PROJECT_ID", nil),
          credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
        )

        # Read file content
        file_content = File.read(file_path)

        # Use document text detection for PDFs
        response = vision.document_text_detection(content: file_content, mime_type: "application/pdf")

        # Extract full text annotation
        response.full_text_annotation&.text || ""
      else
        # Fallback: simulate OCR for development
        simulate_ocr_extraction
      end
    ensure
      FileUtils.rm_f(file_path) if File.exist?(file_path)
    end
  end

  # Extract text from image using Google Vision
  def extract_from_image
    file_path = download_file

    begin
      # Check if Google credentials are available
      if google_credentials_available?
        vision = Google::Cloud::Vision.new(
          project_id: ENV.fetch("GOOGLE_PROJECT_ID", nil),
          credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
        )

        # Read file content
        file_content = File.read(file_path)

        # Use document text detection for better accuracy with documents
        response = vision.document_text_detection(content: file_content, mime_type: @file.content_type)

        # Extract full text annotation
        response.full_text_annotation&.text || ""
      else
        # Fallback: simulate OCR for development
        simulate_ocr_extraction
      end
    ensure
      FileUtils.rm_f(file_path) if File.exist?(file_path)
    end
  end

  # Download file to temp location
  def download_file
    file = Tempfile.new([ "invoice_", ".#{@file.filename.extension}" ])
    file.binmode
    file.write(@file.blob.download)
    file.close
    file.path
  end

  # Check if Google credentials are available
  def google_credentials_available?
    ENV["GOOGLE_PROJECT_ID"].present? && ENV["GOOGLE_APPLICATION_CREDENTIALS"].present?
  end

  # Simulate OCR extraction for development without Google credentials
  def simulate_ocr_extraction
    # Simulate extracted text based on filename
    filename = @file.original_filename.to_s.downcase

    case filename
    when /invoice|receipt/
      "INVOICE\n\nDate: #{Date.current.strftime('%B %d, %Y')}\nMerchant: Demo Store\nProduct: #{filename.gsub(/\.[^.]+\z/, '').humanize}\nAmount: $99.99\nWarranty: 12 months"
    when /warranty/
      "WARRANTY\n\nProduct: #{filename.gsub(/\.[^.]+\z/, '').humanize}\nBrand: Demo Brand\nDuration: 24 months\nPurchase Date: #{(Date.current - 30).strftime('%B %d, %Y')}"
    else
      "DOCUMENT\n\nTitle: #{filename.gsub(/\.[^.]+\z/, '').humanize}\nDate: #{Date.current.strftime('%B %d, %Y')}\nType: #{filename.split('.').last.upcase}"
    end
  end
end
