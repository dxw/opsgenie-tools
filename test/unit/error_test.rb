require "test_helper"
require "opsgenie_tools"

class ErrorTest < Minitest::Test
  def test_error_is_a_standard_error
    assert_operator OpsgenieTools::Error, :<, StandardError
  end

  def test_error_carries_a_message
    error = assert_raises(OpsgenieTools::Error) { raise OpsgenieTools::Error, "boom" }
    assert_equal "boom", error.message
  end
end
