require "test_helper"
require "date"

class NextOncallCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    @argv = ARGV.dup
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["OPSGENIE_SCHEDULE_ID"] = "sched-1"
    ENV["OPSGENIE_ROTATION_ID"] = "rot-1"
    ENV["LOOK_AHEAD_MONTHS"] = "6"
    ARGV.replace(%w[-e second@example.invalid])
    reset_gem_user_cache
  end

  def teardown
    ENV.replace(@env)
    ARGV.replace(@argv)
  end

  # The script compares period.start_date > DateTime.now, so its output
  # depends on today's date relative to the fixture unless the periods are
  # far enough in the future to always be "next". Using 2099 keeps this
  # assertion stable without needing to freeze DateTime.now.
  def far_future_timeline
    { "data" => { "finalTimeline" => { "rotations" => [
      { "id" => "rot-1", "name" => "Primary", "periods" => [
        { "startDate" => "2099-01-07T10:00:00Z", "endDate" => "2099-01-14T10:00:00Z",
          "recipient" => { "id" => "user-2" } }
      ] } ] } } }
  end

  def test_output_is_unchanged
    stub_schedule("sched-1")
    stub_timeline("sched-1", body: far_future_timeline)
    stub_users
    load_script("next-oncall.rb")

    out, err = capture_io { main }

    assert_matches_baseline("next-oncall", out)
    assert_equal "", err
  end
end
