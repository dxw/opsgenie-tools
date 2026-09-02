require "test_helper"
require "date"
require "opsgenie_tools"

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

  # NUM_DAYS=7, TAGS=OOH from setup: this is exactly what M2 (Date.today - 30
  # instead of Date.today - num_days) would get wrong.
  def expected_query
    OpsgenieTools::Query.created_after(Date.today - 7, tags: %w[OOH])
  end

  def test_output_is_unchanged
    stub_alerts_pages(fixture("alerts_toil_week"), [], query: expected_query)
    load_script("calculate-toil.rb")

    out, err = capture_io { main }

    assert_matches_baseline("calculate-toil", out)
    assert_equal "", err
  end

  def test_api_error_aborts
    stub_alerts_page(alerts: [], status: 500, body: "upstream boom", query: expected_query)
    load_script("calculate-toil.rb")

    error = assert_raises(SystemExit) { capture_io { main } }
    assert_equal 1, error.status
  end

  # This is the exact behaviour R4 exists to protect: an acknowledged alert
  # that names no acknowledger is warned about on stderr and never reaches
  # the per-alert log or the summary.
  def test_a_malformed_created_at_aborts_with_a_message
    stub_alerts_pages(fixture("alerts_malformed_created_at"), [], query: expected_query)
    load_script("calculate-toil.rb")

    err = nil
    _out, err = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/alert 77 has an unusable createdAt/, err)
  end

  def test_an_alert_with_no_acknowledger_is_warned_about_and_skipped
    stub_alerts_pages(fixture("alerts_missing_acknowledger"), [], query: expected_query)
    load_script("calculate-toil.rb")

    out, err = capture_io { main }

    assert_matches_baseline("calculate-toil-missing-acknowledger", out)
    assert_equal "Alert 42 is acknowledged but names no acknowledger; skipping it.\n", err
  end
end
