require "test_helper"
require "date"

class OncallHoursCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["OPSGENIE_SCHEDULE_ID"] = "sched-1"
    ENV["OPSGENIE_ROTATION_ID"] = "rot-1"
    ENV["PAYMENT_RATE"] = "10.00"
    ENV["OPSGENIE_DATE"] = "2026-09-10"
    ENV.delete("DEBUG")
    reset_gem_user_cache
  end

  def teardown
    ENV.replace(@env)
  end

  def test_output_is_unchanged
    stub_schedule("sched-1")
    stub_timeline("sched-1")
    stub_users
    load_script("oncall-hours.rb")

    out, err = capture_io { main }

    assert_matches_baseline("oncall-hours", out)
    assert_equal "", err
  end
end
