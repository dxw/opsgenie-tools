require "test_helper"
require "opsgenie_tools"
require "date"

class OnCallTest < Minitest::Test
  O = OpsgenieTools::OnCall

  Period = Struct.new(:start_date, :user)
  User = Struct.new(:username)

  def test_next_wednesday_from_a_monday
    assert_equal Date.new(2026, 9, 2), O.next_wednesday(today: Date.new(2026, 8, 31))
  end

  def test_next_wednesday_on_a_wednesday_is_today
    assert_equal Date.new(2026, 9, 2), O.next_wednesday(today: Date.new(2026, 9, 2))
  end

  def test_next_wednesday_from_a_thursday_is_next_week
    assert_equal Date.new(2026, 9, 9), O.next_wednesday(today: Date.new(2026, 9, 3))
  end

  def test_slack_name
    map = { "first@example.invalid" => "first" }

    assert_equal "first", O.slack_name("first@example.invalid", map)
    assert_equal "Unknown", O.slack_name("nobody@example.invalid", map)
    assert_equal "Unknown", O.slack_name(nil, map)
  end

  def test_next_period_for_returns_the_earliest_future_period
    periods = [
      Period.new(DateTime.new(2026, 10, 7, 10), User.new("first@example.invalid")),
      Period.new(DateTime.new(2026, 9, 9, 10), User.new("first@example.invalid")),
      Period.new(DateTime.new(2026, 9, 16, 10), User.new("second@example.invalid"))
    ]

    found = O.next_period_for(periods, username: "first@example.invalid",
                                       after: DateTime.new(2026, 9, 3))

    assert_equal DateTime.new(2026, 9, 9, 10), found.start_date
  end

  def test_next_period_for_ignores_the_past_and_unassigned_slots
    periods = [
      Period.new(DateTime.new(2026, 8, 5, 10), User.new("first@example.invalid")),
      Period.new(DateTime.new(2026, 9, 9, 10), nil)
    ]

    assert_nil O.next_period_for(periods, username: "first@example.invalid",
                                          after: DateTime.new(2026, 9, 3))
  end
end
