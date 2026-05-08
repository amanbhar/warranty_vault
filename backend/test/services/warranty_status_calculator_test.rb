# frozen_string_literal: true

require "test_helper"
require "ostruct"

class WarrantyStatusCalculatorTest < ActiveSupport::TestCase
  test "product status is active when at least one warranty is active" do
    warranties = [
      OpenStruct.new(expires_at: 10.days.ago.to_date),
      OpenStruct.new(expires_at: 120.days.from_now.to_date)
    ]

    assert_equal "active", WarrantyStatusCalculator.product_status(warranties)
  end

  test "product status is expiring when no active warranties but one is expiring" do
    warranties = [
      OpenStruct.new(expires_at: 5.days.ago.to_date),
      OpenStruct.new(expires_at: 10.days.from_now.to_date)
    ]

    assert_equal "expiring", WarrantyStatusCalculator.product_status(warranties)
  end

  test "product status is expired when all warranties are expired" do
    warranties = [
      OpenStruct.new(expires_at: 40.days.ago.to_date),
      OpenStruct.new(expires_at: 1.day.ago.to_date)
    ]

    assert_equal "expired", WarrantyStatusCalculator.product_status(warranties)
  end

  test "product status defaults to expired when no warranties exist" do
    assert_equal "expired", WarrantyStatusCalculator.product_status([])
  end
end
