# frozen_string_literal: true

class AiExtractionService
  def self.process_file_stateless(uploaded_file)
    file_path = uploaded_file.tempfile.path
    mime_type = uploaded_file.content_type

    # 1. Pull Raw Text (handling various invoice formats natively)
    raw_text = extract_raw_text(file_path, mime_type)
    return { success: false, error: "Empty document or unsupported format" } if raw_text.blank?

    # 2. Extract Data directly through the generic text scanner interface without DB models
    AiServiceManager.extract_from_text(raw_text)
  rescue StandardError => e
    Rails.logger.error "[AiExtractionService] File scan error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def self.extract_raw_text(file_path, mime_type)
    case mime_type
    when "application/pdf"
      extract_from_pdf(file_path)
    when "image/jpeg", "image/png", "image/jpg", "image/webp"
      extract_from_image(file_path, mime_type)
    else
      File.read(file_path, encoding: "UTF-8", mode: "rb").gsub(/[^\x20-\x7E\n]/, "").strip
    end
  rescue StandardError => e
    Rails.logger.error "[AiExtractionService] Failed to extract raw text: #{e.message}"
    ""
  end

  def self.extract_from_pdf(path)
    require "pdf-reader"
    PDF::Reader.new(path).pages.map(&:text).join("\n").strip
  rescue LoadError
    File.read(path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "").strip
  end

  def self.extract_from_image(path, mime_type)
    # Use Google Cloud Vision or OpenAI directly for stateless images
    if ENV["GOOGLE_PROJECT_ID"].present? && ENV["GOOGLE_APPLICATION_CREDENTIALS"].present?
      require "google/cloud/vision"
      vision = Google::Cloud::Vision.new(
        project_id: ENV.fetch("GOOGLE_PROJECT_ID"),
        credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS")
      )
      file_content = File.read(path)
      response = vision.document_text_detection(content: file_content, mime_type: mime_type)
      response.full_text_annotation&.text || ""
    else
      # If Vision API is unavailable, fallback to OpenAI directly since we need stateless extraction
      client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
      file_content = Base64.encode64(File.read(path))

      response = client.chat(
        parameters: {
          model: Rails.application.config.ai_services.openai_model,
          messages: [
            {
              role: "user",
              content: [
                { type: "text", text: "Extract all text from this invoice image. Return only the raw text content." },
                { type: "image_url", image_url: { url: "data:#{mime_type};base64,#{file_content}" } }
              ]
            }
          ]
        }
      )
      response.dig("choices", 0, "message", "content") || ""
    end
  end
end
