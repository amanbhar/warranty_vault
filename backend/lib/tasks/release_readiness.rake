# frozen_string_literal: true

namespace :release do
  desc "Run production readiness checks for env, Redis, Sidekiq schedule, and ActionCable config"
  task check: :environment do
    required_env = %w[
      RAILS_ENV
      REDIS_URL
      APP_URL
      FRONTEND_URL
      ACTION_CABLE_URL
      SMTP_DOMAIN
      SMTP_USERNAME
      SMTP_PASSWORD
    ]

    missing_env = required_env.select { |key| ENV[key].blank? }
    if missing_env.any?
      puts "FAIL missing env vars: #{missing_env.join(', ')}"
      abort "release:check failed"
    end
    puts "PASS env vars present"

    begin
      redis_info = Sidekiq.redis { |conn| conn.ping }
      puts "PASS redis ping: #{redis_info}"
    rescue => e
      puts "FAIL redis ping: #{e.message}"
      abort "release:check failed"
    end

    begin
      schedule_keys = Sidekiq.get_all_schedules.keys
      required_jobs = %w[process_due_reminders]
      missing_jobs = required_jobs - schedule_keys
      if missing_jobs.any?
        puts "FAIL missing sidekiq schedules: #{missing_jobs.join(', ')}"
        abort "release:check failed"
      end
      puts "PASS sidekiq schedules present: #{required_jobs.join(', ')}"
    rescue => e
      puts "FAIL sidekiq schedule check: #{e.message}"
      abort "release:check failed"
    end

    begin
      cable_url = Rails.application.config.action_cable.url
      origins = Rails.application.config.action_cable.allowed_request_origins
      if cable_url.blank?
        puts "FAIL action_cable.url is blank"
        abort "release:check failed"
      end

      puts "PASS action_cable.url=#{cable_url}"
      puts "PASS action_cable.allowed_request_origins=#{origins.inspect}"
    rescue => e
      puts "FAIL action cable config check: #{e.message}"
      abort "release:check failed"
    end

    puts "PASS release readiness checks completed"
  end
end
