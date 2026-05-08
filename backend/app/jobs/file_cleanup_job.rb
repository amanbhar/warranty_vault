# Scheduled job to clean up old unused files
# Runs weekly to remove orphaned Active Storage blobs
class FileCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[FileCleanupJob] Starting weekly file cleanup"

    # Clean up unused Active Storage blobs
    FileStorageService.cleanup_old_files

    # Clean up temp files older than 24 hours
    clean_temp_files

    Rails.logger.info "[FileCleanupJob] File cleanup completed"
  end

  private

  def clean_temp_files
    temp_dir = Rails.root.join("tmp", "uploads")
    return unless Dir.exist?(temp_dir)

    # Find files older than 24 hours
    cutoff_time = 24.hours.ago

    Dir.glob(File.join(temp_dir, "**", "*")).each do |file|
      next if File.directory?(file)

      if File.mtime(file) < cutoff_time
        File.delete(file)
        Rails.logger.info "[FileCleanupJob] Deleted temp file: #{file}"
      end
    end
  end
end
