require "test_helper"
require "opsgenie_tools"

# Every module that reads an alert's timestamp goes through this, so that a
# malformed alert reaches the operator as OpsgenieTools::Error — the one
# exception the scripts rescue — rather than as a KeyError, TypeError or
# ArgumentError stack trace.
class CreatedAtTest < Minitest::Test
  def test_parses_a_usable_timestamp
    assert_equal Time.utc(2026, 8, 26, 3, 40, 0),
                 OpsgenieTools.created_at("createdAt" => "2026-08-26T03:40:00.000Z")
  end

  def test_a_missing_key_raises_an_opsgenie_error
    error = assert_raises(OpsgenieTools::Error) do
      OpsgenieTools.created_at("tinyId" => "42")
    end

    assert_match(/alert 42 has no createdAt/, error.message)
  end

  def test_a_null_value_raises_an_opsgenie_error
    error = assert_raises(OpsgenieTools::Error) do
      OpsgenieTools.created_at("tinyId" => "42", "createdAt" => nil)
    end

    assert_match(/alert 42 has an unusable createdAt/, error.message)
  end

  def test_an_unparseable_value_raises_an_opsgenie_error
    error = assert_raises(OpsgenieTools::Error) do
      OpsgenieTools.created_at("tinyId" => "42", "createdAt" => "not a date")
    end

    assert_match(/alert 42 has an unusable createdAt/, error.message)
  end

  def test_falls_back_to_the_id_then_to_a_placeholder
    by_id = assert_raises(OpsgenieTools::Error) do
      OpsgenieTools.created_at("id" => "abc-123")
    end
    assert_match(/alert abc-123 /, by_id.message)

    anonymous = assert_raises(OpsgenieTools::Error) { OpsgenieTools.created_at({}) }
    assert_match(/alert \(unidentified\) /, anonymous.message)
  end
end
