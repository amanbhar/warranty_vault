# frozen_string_literal: true

require "test_helper"

class ProcessDueRemindersJobTest < ActiveJob::TestCase
  test "delegates processing to notification service" do
    called = false

    NotificationServiceV2.stub(:process_due_reminders, -> {
      called = true
      { due: 0, sent: 0, skipped: 0, failed: 0 }
    }) do
      ProcessDueRemindersJob.perform_now
    end

    assert called
  end
end
