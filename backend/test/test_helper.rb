# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
ActiveJob::Base.queue_adapter = :test

# Load test helpers
require_relative "test_helpers/warranty_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup fixtures
    fixtures :all

    # Add more helper methods to be used by all tests here
    include WarrantyTestHelpers

    # Helper to assert about enqueued jobs
    def assert_enqueued_jobs(count, only: nil)
      initial_count = only ? ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == only }.size : ActiveJob::Base.queue_adapter.enqueued_jobs.size

      if block_given?
        yield
      else
        final_count = only ? ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == only }.size : ActiveJob::Base.queue_adapter.enqueued_jobs.size
        assert_equal count, final_count, "Expected #{count} jobs to be enqueued"
        return
      end

      final_count = only ? ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == only }.size : ActiveJob::Base.queue_adapter.enqueued_jobs.size

      assert_equal count, final_count - initial_count, "Expected #{count} jobs to be enqueued"
    end

    def assert_no_enqueued_jobs
      if block_given?
        assert_enqueued_jobs(0) { yield }
      else
        assert_enqueued_jobs(0)
      end
    end

    def clear_enqueued_jobs
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end
  end
end

module ActionDispatch
  class IntegrationTest
    include WarrantyTestHelpers

    # Helper to make authenticated requests
    def authenticated_headers(token)
      { "Authorization" => "Bearer #{token}" }
    end
  end
end
