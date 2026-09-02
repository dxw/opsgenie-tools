require "test_helper"
require "date"
require "minitest/mock"

class OncallCharacterisationTest < Minitest::Test
  FROZEN_TODAY = Date.new(2026, 9, 2).freeze

  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["OPSGENIE_SCHEDULE_ID"] = "sched-1"
    ENV["OPSGENIE_SCHEDULE_ID_SECONDLINE"] = "sched-2"
    ENV["OPSGENIE_WEEKS"] = "2"
    ENV["EMAIL_TO_SLACK_MAP"] = '{"first@example.invalid":"first","second@example.invalid":"second"}'
    reset_gem_user_cache
  end

  def teardown
    ENV.replace(@env)
  end

  # The second line schedule returns nobody, which the script currently
  # handles by leaving $second_slack_name at its previous value. This
  # baseline therefore pins that defect; Task 7 fixes it and updates it.
  def test_output_is_unchanged
    stub_schedule("sched-1")
    stub_schedule("sched-2", name: "OOH Second Line")
    stub_on_calls("sched-1")
    stub_on_calls("sched-2", body: { "data" => { "onCallParticipants" => [] } })
    stub_users
    load_script("oncall.rb")

    out, err = capture_io { Date.stub(:today, FROZEN_TODAY) { main } }

    assert_matches_baseline("oncall", out)
    assert_equal "", err
  end
end
