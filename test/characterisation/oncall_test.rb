require "test_helper"
require "date"
require "minitest/mock"

class OncallCharacterisationTest < Minitest::Test
  FROZEN_TODAY = Date.new(2026, 9, 2).freeze
  HANDOVER_DATE = /\A2026-09-(02|09)T19:00:00\+00:00\z/.freeze

  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["OPSGENIE_SCHEDULE_ID"] = "sched-1"
    ENV["OPSGENIE_SCHEDULE_ID_SECONDLINE"] = "sched-2"
    ENV["OPSGENIE_WEEKS"] = "2"
    ENV["EMAIL_TO_SLACK_MAP"] = '{"first@example.invalid":"first","second@example.invalid":"second"}'
    reset_gem_user_cache
    # Load before any test deletes a variable: loading runs Dotenv.load, which
    # would put back whatever .env supplies for the one under test.
    load_script("oncall.rb")
  end

  def teardown
    ENV.replace(@env)
  end

  # The second line schedule returns nobody, so this pins that a gap in the
  # rota reads as "Nobody" rather than repeating the previous week's name.
  def test_a_malformed_slack_map_aborts_with_a_message
    ENV["EMAIL_TO_SLACK_MAP"] = '{"first@example.invalid": oops}'

    _out, err = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/EMAIL_TO_SLACK_MAP is not valid JSON/, err)
  end

  def test_output_is_unchanged
    stub_schedule("sched-1")
    stub_schedule("sched-2", name: "OOH Second Line")
    stub_on_calls("sched-1", query: { "date" => HANDOVER_DATE })
    stub_on_calls("sched-2", body: { "data" => { "onCallParticipants" => [] } },
                             query: { "date" => HANDOVER_DATE })
    stub_users

    out, err = capture_io { Date.stub(:today, FROZEN_TODAY) { main } }

    assert_matches_baseline("oncall", out)
    assert_equal "", err
  end

  def test_both_lines_named_when_both_are_covered
    stub_schedule("sched-1")
    stub_schedule("sched-2", name: "OOH Second Line")
    stub_on_calls("sched-1", query: { "date" => HANDOVER_DATE })
    stub_on_calls("sched-2",
                  body: { "data" => { "onCallParticipants" =>
                          [{ "type" => "user", "name" => "second@example.invalid" }] } },
                  query: { "date" => HANDOVER_DATE })
    stub_users

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
    stub_on_calls("sched-1", query: { "date" => HANDOVER_DATE })
    stub_request(:get, %r{/v2/schedules/sched-2/on-calls})
      .with(query: hash_including("date" => "2026-09-02T19:00:00+00:00"))
      .to_return(status: 200, body: JSON.dump("data" => { "onCallParticipants" =>
                 [{ "type" => "user", "name" => "second@example.invalid" }] }),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, %r{/v2/schedules/sched-2/on-calls})
      .with(query: hash_including("date" => "2026-09-09T19:00:00+00:00"))
      .to_return(status: 200, body: JSON.dump("data" => { "onCallParticipants" => [] }),
                 headers: { "Content-Type" => "application/json" })
    stub_users

    out, = capture_io { Date.stub(:today, FROZEN_TODAY) { main } }

    lines = out.lines
    assert_match(/2026-09-02: @first \/ @second/, lines[1])
    assert_match(/2026-09-09: @first \/ Nobody/, lines[2])
  end

  def test_an_unset_email_to_slack_map_refuses_to_run
    ENV.delete("EMAIL_TO_SLACK_MAP")

    _, err = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/EMAIL_TO_SLACK_MAP/, err)
  end
end
