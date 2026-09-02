require "test_helper"
require "opsgenie_tools"

class ToilTest < Minitest::Test
  USER = "first@example.invalid".freeze
  OTHER = "second@example.invalid".freeze

  def alert(created, category, user: USER, acknowledged: true)
    {
      "tinyId" => created,
      "acknowledged" => acknowledged,
      "report" => user.nil? ? nil : { "acknowledgedBy" => user },
      "createdAt" => created,
      "tags" => ["OOH", category].compact
    }
  end

  def calculate(alerts, **kwargs)
    OpsgenieTools::Toil.calculate(alerts, sleeping: 0.5, waking: 0.25, **kwargs)
  end

  # The regression this library exists to prevent: the API returns alerts
  # newest first, and a de-dup that trusts arrival order silently drops all but
  # the first alert per user and category.
  def test_descending_input_gives_the_same_result_as_ascending
    ascending = [
      alert("2026-08-25T01:10:00Z", "sleepinghours"),
      alert("2026-08-26T03:40:00Z", "sleepinghours"),
      alert("2026-08-27T02:05:00Z", "sleepinghours"),
      alert("2026-08-27T21:30:00Z", "wakinghours")
    ]

    assert_equal calculate(ascending), calculate(ascending.reverse)
    assert_equal 1.75, calculate(ascending.reverse).fetch(USER).fetch("toil")
  end

  def test_alerts_more_than_the_window_apart_both_count
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-26T03:30:01Z", "sleepinghours")]

    assert_equal 2, calculate(alerts).fetch(USER).fetch("sleepinghours")
  end

  def test_alerts_exactly_the_window_apart_count_once
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-26T03:30:00Z", "sleepinghours")]

    assert_equal 1, calculate(alerts).fetch(USER).fetch("sleepinghours")
  end

  def test_the_window_is_per_user
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-26T03:05:00Z", "sleepinghours", user: OTHER)]

    result = calculate(alerts)
    assert_equal 1, result.fetch(USER).fetch("sleepinghours")
    assert_equal 1, result.fetch(OTHER).fetch("sleepinghours")
  end

  def test_the_window_is_per_category
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-26T03:05:00Z", "wakinghours")]

    result = calculate(alerts).fetch(USER)
    assert_equal 1, result.fetch("sleepinghours")
    assert_equal 1, result.fetch("wakinghours")
    assert_equal 0.75, result.fetch("toil")
  end

  def test_unacknowledged_alerts_are_ignored
    assert_empty calculate([alert("2026-08-26T03:00:00Z", "sleepinghours", acknowledged: false)])
  end

  def test_alerts_with_neither_time_tag_are_ignored
    assert_empty calculate([alert("2026-08-26T03:00:00Z", nil)])
  end

  def test_an_alert_with_both_tags_counts_as_sleeping
    both = alert("2026-08-26T03:00:00Z", "sleepinghours")
    both["tags"] << "wakinghours"

    result = calculate([both]).fetch(USER)
    assert_equal 1, result.fetch("sleepinghours")
    assert_equal 0, result.fetch("wakinghours")
  end

  def test_a_missing_acknowledger_is_reported_and_not_counted
    reported = []

    assert_empty calculate([alert("2026-08-26T03:00:00Z", "sleepinghours", user: nil)],
                           on_missing_acknowledger: ->(a) { reported << a })
    assert_equal 1, reported.length
  end

  def test_a_missing_created_at_raises_an_opsgenie_error
    broken = alert("2026-08-26T03:00:00Z", "sleepinghours")
    broken.delete("createdAt")

    error = assert_raises(OpsgenieTools::Error) { calculate([broken]) }
    assert_match(/has no createdAt/, error.message)
    assert_match(/2026-08-26T03:00:00Z/, error.message)
  end

  def test_a_null_created_at_raises_an_opsgenie_error
    broken = alert("2026-08-26T03:00:00Z", "sleepinghours")
    broken["createdAt"] = nil

    error = assert_raises(OpsgenieTools::Error) { calculate([broken]) }
    assert_match(/unusable createdAt/, error.message)
  end

  def test_an_unparseable_created_at_raises_an_opsgenie_error
    broken = alert("2026-08-26T03:00:00Z", "sleepinghours")
    broken["createdAt"] = "not a date"

    error = assert_raises(OpsgenieTools::Error) { calculate([broken]) }
    assert_match(/unusable createdAt/, error.message)
  end

  def test_by_month_buckets_the_toil
    alerts = [alert("2026-07-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-26T03:00:00Z", "sleepinghours"),
              alert("2026-08-27T21:30:00Z", "wakinghours")]

    assert_equal({ "2026-07" => 0.5, "2026-08" => 0.75 },
                 OpsgenieTools::Toil.by_month(alerts, sleeping: 0.5, waking: 0.25))
  end

  # by_month is per-period, not per-person, so unlike calculate it has always
  # counted an alert that names no acknowledger rather than discarding it.
  def test_by_month_counts_an_alert_with_no_acknowledger
    reported = []
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours", user: nil)]

    result = OpsgenieTools::Toil.by_month(alerts, sleeping: 0.5, waking: 0.25,
                                           on_missing_acknowledger: ->(a) { reported << a })

    assert_equal({ "2026-08" => 0.5 }, result)
    assert_equal 1, reported.length
  end

  def test_by_month_dedupes_unattributed_alerts_within_the_window
    alerts = [alert("2026-08-26T03:00:00Z", "sleepinghours", user: nil),
              alert("2026-08-26T03:15:00Z", "sleepinghours", user: nil)]

    assert_equal({ "2026-08" => 0.5 },
                 OpsgenieTools::Toil.by_month(alerts, sleeping: 0.5, waking: 0.25))
  end

  # Mirrors test_descending_input_gives_the_same_result_as_ascending: by_month
  # must sort too, since fetch_ooh_alerts concatenates per-month pages that
  # each arrive newest-first.
  def test_by_month_descending_input_gives_the_same_result_as_ascending
    ascending = [
      alert("2026-08-25T01:10:00Z", "sleepinghours"),
      alert("2026-08-26T03:40:00Z", "sleepinghours"),
      alert("2026-08-27T02:05:00Z", "sleepinghours"),
      alert("2026-08-27T21:30:00Z", "wakinghours")
    ]

    ascending_result = OpsgenieTools::Toil.by_month(ascending, sleeping: 0.5, waking: 0.25)
    descending_result = OpsgenieTools::Toil.by_month(ascending.reverse, sleeping: 0.5, waking: 0.25)

    assert_equal ascending_result, descending_result
    assert_equal({ "2026-08" => 1.75 }, descending_result)
  end
end
