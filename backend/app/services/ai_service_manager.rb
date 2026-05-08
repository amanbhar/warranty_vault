# frozen_string_literal: true

require "ostruct"

# AI Service Manager - Manages multiple AI services with fallback
#
# Features:
# 1. Configurable primary and fallback AI services
# 2. Automatic service selection based on environment
# 3. Fallback mechanism when primary service fails
# 4. Service health monitoring
# 5. Load balancing capabilities
#
# Usage:
#   AiServiceManager.process_invoice(invoice)
#   AiServiceManager.extract_from_text(text)
class AiServiceManager
  class ServiceError < StandardError; end
  class ConfigurationError < StandardError; end

  # Service configuration from Rails config
  PRIMARY_SERVICE = Rails.application.config.ai_services.primary
  FALLBACK_SERVICE = Rails.application.config.ai_services.fallback

  # Available services
  AVAILABLE_SERVICES = {
    "gemini" => GeminiInvoiceScanner,
    "openai" => OpenAiInvoiceScanner
  }.freeze

  # Service health tracking
  @service_health = {}
  @last_health_check = {}

  class << self
    # Main entry point for invoice processing
    def process_invoice(invoice)
      service_name = select_service
      service_class = AVAILABLE_SERVICES[service_name]

      Rails.logger.info "[AiServiceManager] Using #{service_name} for invoice #{invoice.id}"

      begin
        result = service_class.new(invoice).process

        if result[:success]
          record_service_success(service_name)
          result
        else
          Rails.logger.warn "[AiServiceManager] #{service_name} reported failure: #{result[:error]}"

          # Try fallback service on failure
          if service_name != FALLBACK_SERVICE
            Rails.logger.info "[AiServiceManager] Falling back to #{FALLBACK_SERVICE} due to result failure"
            try_fallback_service(invoice)
          else
            record_service_failure(service_name, StandardError.new(result[:error]))
            result
          end
        end
      rescue => e
        Rails.logger.warn "[AiServiceManager] #{service_name} raised error: #{e.message}"
        record_service_failure(service_name, e)

        # Try fallback service on raised exception
        if service_name != FALLBACK_SERVICE
          Rails.logger.info "[AiServiceManager] Falling back to #{FALLBACK_SERVICE}"
          try_fallback_service(invoice)
        else
          Rails.logger.error "[AiServiceManager] All AI services failed for invoice #{invoice.id}"
          { success: false, error: "All AI services failed: #{e.message}" }
        end
      end
    end

    # Extract data from text using AI
    def extract_from_text(text)
      service_name = select_service
      service_class = AVAILABLE_SERVICES[service_name]

      # Create a temporary invoice object for text processing
      temp_invoice = OpenStruct.new(id: "temp", file: nil)

      begin
        # Use the service's text extraction capabilities
        if service_class.respond_to?(:scan_text)
          result = service_class.scan_text(text)
        else
          # Fallback to processing with mock invoice
          result = service_class.new(temp_invoice).send(:extract_structured_data, text)
        end

        if result[:success]
          record_service_success(service_name)
          result
        else
          Rails.logger.warn "[AiServiceManager] #{service_name} reported failure: #{result[:error]}"

          if service_name != FALLBACK_SERVICE
            Rails.logger.info "[AiServiceManager] Falling back to #{FALLBACK_SERVICE} for text extraction"
            try_fallback_text_extraction(text)
          else
            record_service_failure(service_name, StandardError.new(result[:error]))
            result
          end
        end
      rescue => e
        Rails.logger.warn "[AiServiceManager] #{service_name} text extraction failed: #{e.message}"
        record_service_failure(service_name, e)

        # Try fallback service
        if service_name != FALLBACK_SERVICE
          Rails.logger.info "[AiServiceManager] Falling back to #{FALLBACK_SERVICE} for text extraction"
          try_fallback_text_extraction(text)
        else
          Rails.logger.error "[AiServiceManager] All AI services failed for text extraction"
          { success: false, error: "All AI services failed: #{e.message}" }
        end
      end
    end

    # Get current service configuration
    def service_configuration
      {
        primary_service: PRIMARY_SERVICE,
        fallback_service: FALLBACK_SERVICE,
        available_services: AVAILABLE_SERVICES.keys,
        service_health: @service_health,
        environment_config: {
          gemini: {
            model: Rails.application.config.ai_services.gemini_model,
            temperature: Rails.application.config.ai_services.gemini_temperature,
            max_tokens: Rails.application.config.ai_services.gemini_max_tokens,
            api_key_present: ENV["GEMINI_API_KEY"].present?
          },
          openai: {
            model: Rails.application.config.ai_services.openai_model,
            temperature: Rails.application.config.ai_services.openai_temperature,
            max_tokens: Rails.application.config.ai_services.openai_max_tokens,
            api_key_present: ENV["OPENAI_API_KEY"].present?
          }
        }
      }
    end

    # Check service health
    def check_service_health
      AVAILABLE_SERVICES.each do |service_name, service_class|
        begin
          # Try to initialize the service
          service_class.new(nil)
          model = case service_name
          when "gemini"
                    Rails.application.config.ai_services.gemini_model
          when "openai"
                    Rails.application.config.ai_services.openai_model
          else
                    "unknown"
          end
          @service_health[service_name] = {
            status: "healthy",
            last_check: Time.current,
            error: nil,
            model: model
          }
        rescue => e
          @service_health[service_name] = {
            status: "unhealthy",
            last_check: Time.current,
            error: e.message
          }
        end
      end

      @service_health
    end

    # Force use of specific service
    def with_service(service_name)
      return yield unless AVAILABLE_SERVICES.key?(service_name)

      original_primary = PRIMARY_SERVICE
      ENV["PRIMARY_AI_SERVICE"] = service_name

      begin
        result = yield
        ENV["PRIMARY_AI_SERVICE"] = original_primary
        result
      rescue => e
        ENV["PRIMARY_AI_SERVICE"] = original_primary
        raise e
      end
    end

    # Get current AI model being used
    def get_current_ai_model
      service = PRIMARY_SERVICE

      case service
      when "gemini"
        Rails.application.config.ai_services.gemini_model
      when "openai"
        Rails.application.config.ai_services.openai_model
      else
        "unknown"
      end
    end

    private

    # Select best service based on configuration and health
    def select_service
      # Check if primary service is healthy
      primary_health = @service_health[PRIMARY_SERVICE]

      if primary_health && primary_health[:status] == "healthy"
        return PRIMARY_SERVICE
      end

      # Check fallback service
      fallback_health = @service_health[FALLBACK_SERVICE]

      if fallback_health && fallback_health[:status] == "healthy"
        Rails.logger.warn "[AiServiceManager] Primary service unhealthy, using fallback: #{FALLBACK_SERVICE}"
        return FALLBACK_SERVICE
      end

      # Default to primary service
      PRIMARY_SERVICE
    end

    # Try fallback service for invoice processing
    def try_fallback_service(invoice)
      fallback_class = AVAILABLE_SERVICES[FALLBACK_SERVICE]

      begin
        result = fallback_class.new(invoice).process
        if result[:success]
          record_service_success(FALLBACK_SERVICE)
        else
          record_service_failure(FALLBACK_SERVICE, StandardError.new(result[:error]))
        end
        result
      rescue => e
        Rails.logger.error "[AiServiceManager] Fallback service #{FALLBACK_SERVICE} also failed: #{e.message}"
        record_service_failure(FALLBACK_SERVICE, e)
        { success: false, error: "Fallback service failed: #{e.message}" }
      end
    end

    # Try fallback service for text extraction
    def try_fallback_text_extraction(text)
      fallback_class = AVAILABLE_SERVICES[FALLBACK_SERVICE]

      begin
        if fallback_class.respond_to?(:scan_text)
          result = fallback_class.scan_text(text)
        else
          temp_invoice = OpenStruct.new(id: "temp", file: nil)
          result = fallback_class.new(temp_invoice).send(:extract_structured_data, text)
        end

        if result[:success]
          record_service_success(FALLBACK_SERVICE)
        else
          record_service_failure(FALLBACK_SERVICE, StandardError.new(result[:error]))
        end
        result
      rescue => e
        Rails.logger.error "[AiServiceManager] Fallback text extraction failed: #{e.message}"
        record_service_failure(FALLBACK_SERVICE, e)
        { success: false, error: "Fallback text extraction failed: #{e.message}" }
      end
    end

    # Record successful service usage
    def record_service_success(service_name)
      @service_health[service_name] = {
        status: "healthy",
        last_check: Time.current,
        last_success: Time.current,
        error: nil
      }
    end

    # Record service failure
    def record_service_failure(service_name, error)
      @service_health[service_name] = {
        status: "unhealthy",
        last_check: Time.current,
        last_failure: Time.current,
        error: error.message
      }
    end
  end
end
