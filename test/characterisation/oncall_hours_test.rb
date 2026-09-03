require "test_helper"
require "date"
require "minitest/mock"

class OncallHoursCharacterisationTest < Minitest::Test
  # Not the OPSGENIE_DATE window used below — stubbed away from it so a
  # regression that starts reading Date.today instead of the computed
  # window start is caught deterministically, whatever day this runs on
  # (2026-09-02 is itself that window's start, so an unstubbed run could
  # pass by coincidence rather than by pinning the right value).
  UNRELATED_TODAY = Date.new(1999, 1, 1).freeze

  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["OPSGENIE_SCHEDULE_ID"] = "sched-1"
    ENV["OPSGENIE_ROTATION_ID"] = "rot-1"
    ENV["PAYMENT_RATE"] = "10.00"
    ENV["OPSGENIE_DATE"] = "2026-09-10"
    ENV.delete("DEBUG")
    reset_gem_user_cache
    # Load before any test deletes a variable: loading runs Dotenv.load, which
    # would put back whatever .env supplies for the one under test.
    load_script("oncall-hours.rb")
  end

  def teardown
    ENV.replace(@env)
  end

  def test_output_is_unchanged
    stub_schedule("sched-1")
    stub_timeline("sched-1", query: { "date" => "2026-09-02T00:00:00+00:00",
                                       "interval" => "2", "intervalUnit" => "months" })
    stub_users

    out, err = capture_io { Date.stub(:today, UNRELATED_TODAY) { main } }

    assert_matches_baseline("oncall-hours", out)
    assert_equal "", err
  end

  # With no rotation ids nothing matched, so the report printed absolutely
  # nothing and exited 0 — indistinguishable from a month nobody was on call.
  def test_an_empty_rotation_list_refuses_to_run
    ENV.delete("OPSGENIE_ROTATION_ID")
    out, = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/Please set OPSGENIE_ROTATION_ID/, out)
  end

  def test_an_unset_payment_rate_refuses_to_run
    ENV.delete("PAYMENT_RATE")
    out, = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/Please set PAYMENT_RATE/, out)
  end
end
