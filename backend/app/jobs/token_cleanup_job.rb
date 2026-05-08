# frozen_string_literal: true

# Background job to clean up expired verification tokens
class TokenCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform(*args)
    Rails.logger.info "[TokenCleanupJob] Starting expired token cleanup"

    # Clean up expired verification tokens
    cleaned_count = VerificationService.cleanup_expired_tokens

    Rails.logger.info "[TokenCleanupJob] Cleaned up #{cleaned_count} expired verification tokens"

    # Log to monitoring
    Rails.logger.info "[TokenCleanupJob] Token cleanup completed successfully"
  end
end
