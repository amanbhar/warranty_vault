class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to retry if the underlying queue is OK
  # retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Default to Sidekiq queue
  queue_as :default
end
