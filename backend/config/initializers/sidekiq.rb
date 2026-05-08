# Sidekiq configuration file

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  config.error_handlers << ->(ex, ctx, config) {
    Rails.logger.error "Sidekiq error: #{ex.message}"
    Rails.logger.error ctx.inspect
  }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

# Load scheduled jobs from schedule file (server process only)
if Sidekiq.server? && defined?(Sidekiq::Cron::Job)
  schedule_file = Rails.root.join("config", "schedule.yml")
  if schedule_file.exist?
    schedule = YAML.load_file(schedule_file)
    Sidekiq::Cron::Job.load_from_hash!(schedule)
  end
end
