require "test_helper"

class CalculateToilCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["TOIL_SLEEPING_HOURS"] = "0.5"
    ENV["TOIL_WAKING_HOURS"] = "0.25"
    ENV["NUM_DAYS"] = "7"
    ENV["TAGS"] = "OOH"
  end

  def teardown
    ENV.replace(@env)
  end

  def test_output_is_unchanged
    stub_alerts_pages(fixture("alerts_toil_week"), [])
    load_script("calculate-toil.rb")

    out, err = capture_io { main }

    assert_matches_baseline("calculate-toil", out)
    assert_equal "", err
  end

  def test_api_error_aborts
    stub_alerts_page(alerts: [], status: 500, body: "upstream boom")
    load_script("calculate-toil.rb")

    error = assert_raises(SystemExit) { capture_io { main } }
    assert_equal 1, error.status
  end
end
