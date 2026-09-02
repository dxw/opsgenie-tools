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

  # The second line schedule returns nobody, so this pins that a gap in the
  # rota reads as "Nobody" rather than repeating the previous week's name.
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

  def test_both_lines_named_when_both_are_covered
    stub_schedule("sched-1")
    stub_schedule("sched-2", name: "OOH Second Line")
    stub_on_calls("sched-1")
    stub_on_calls("sched-2",
                  body: { "data" => { "onCallParticipants" =>
                          [{ "type" => "user", "name" => "second@example.invalid" }] } })
    stub_users
    load_script("oncall.rb")

    out, = capture_io { Date.stub(:today, FROZEN_TODAY) { main } }

    assert_match(/@first \/ @second/, out)
    refute_match(/Nobody/, out)
  end

  # The old code assigned each week's name to a global inside the loop, so a
  # week with nobody on call reprinted the previous week's name instead of
  # showing the gap. This pins the fix against exactly that shape: week one
  # is covered, week two is not.
  def test_a_gap_does_not_repeat_the_previous_weeks_name
    stub_schedule("sched-1")
    stub_schedule("sched-2", name: "OOH Second Line")
    stub_on_calls("sched-1")
    stub_request(:get, %r{/v2/schedules/sched-2/on-calls})
      .with(query: hash_including("date" => /2026-09-02/))
      .to_return(status: 200, body: JSON.dump("data" => { "onCallParticipants" =>
                 [{ "type" => "user", "name" => "second@example.invalid" }] }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{/v2/schedules/sched-2/on-calls})
      .with(query: hash_including("date" => /2026-09-09/))
      .to_return(status: 200, body: JSON.dump("data" => { "onCallParticipants" => [] }),
                 headers: { "Content-Type" => "application/json" })
    stub_users
    load_script("oncall.rb")

    out, = capture_io { Date.stub(:today, FROZEN_TODAY) { main } }

    lines = out.lines
    assert_match(/2026-09-02: @first \/ @second/, lines[1])
    assert_match(/2026-09-09: @first \/ Nobody/, lines[2])
  end
end
