require "test_helper"
require "opsgenie_tools"
require "date"

class StatsTest < Minitest::Test
  S = OpsgenieTools::Stats

  def test_month_windows_spans_a_year_boundary
    assert_equal [
      [Date.new(2026, 11, 15), Date.new(2026, 12, 1)],
      [Date.new(2026, 12, 1), Date.new(2027, 1, 1)],
      [Date.new(2027, 1, 1), Date.new(2027, 2, 1)],
      [Date.new(2027, 2, 1), Date.new(2027, 2, 3)]
    ], S.month_windows(Date.new(2026, 11, 15), Date.new(2027, 2, 3))
  end

  def test_month_windows_within_one_month
    assert_equal [[Date.new(2026, 8, 1), Date.new(2026, 8, 20)]],
                 S.month_windows(Date.new(2026, 8, 1), Date.new(2026, 8, 20))
  end

  def test_daily_counts_zero_fills
    alerts = [{ "createdAt" => "2026-08-02T01:00:00Z" },
              { "createdAt" => "2026-08-02T02:00:00Z" }]

    assert_equal [["2026-08-01", 0], ["2026-08-02", 2], ["2026-08-03", 0]],
                 S.daily_counts(alerts, Date.new(2026, 8, 1), Date.new(2026, 8, 4))
  end

  def test_monthly_totals
    alerts = [{ "createdAt" => "2026-07-31T23:00:00Z" },
              { "createdAt" => "2026-08-01T00:30:00Z" }]

    assert_equal [["2026-07", 1], ["2026-08", 1]],
                 S.monthly_totals(alerts, Date.new(2026, 7, 1), Date.new(2026, 8, 5))
  end

  def test_daily_counts_raises_an_opsgenie_error_on_a_malformed_alert
    error = assert_raises(OpsgenieTools::Error) do
      S.daily_counts([{ "tinyId" => "7" }], Date.new(2026, 8, 1), Date.new(2026, 8, 4))
    end

    assert_match(/alert 7 has no createdAt/, error.message)
  end

  def test_monthly_totals_raises_an_opsgenie_error_on_a_null_created_at
    error = assert_raises(OpsgenieTools::Error) do
      S.monthly_totals([{ "tinyId" => "7", "createdAt" => nil }],
                       Date.new(2026, 8, 1), Date.new(2026, 8, 4))
    end

    assert_match(/unusable createdAt/, error.message)
  end

  def test_summarise_counts_time_tags_per_business_unit_and_company
    alerts = [
      { "tags" => %w[bu1 OOH sleepinghours client_alpha] },
      { "tags" => %w[bu2 OOH client_beta] },
      { "tags" => %w[OOH] },
      { "tags" => %w[bu1] }
    ]

    summary = S.summarise(alerts, business_units: %w[bu1 bu2],
                                  time_tags: %w[OOH sleepinghours])

    assert_equal 2, summary["company"][:totals]["OOH"]
    assert_equal 1, summary["company"][:totals]["sleepinghours"]
    assert_equal 1, summary["bu1"][:totals]["sleepinghours"]
    assert_equal({ "OOH" => 1, "sleepinghours" => 1 }, summary["bu1"][:clients]["alpha"])
    assert_equal 1, summary["bu2"][:clients]["beta"]["OOH"]
  end

  def test_summarise_ignores_alerts_with_no_business_unit_or_no_time_tag
    summary = S.summarise([{ "tags" => %w[OOH] }, { "tags" => %w[bu1] }],
                          business_units: %w[bu1], time_tags: %w[OOH])

    assert_equal 0, summary["company"][:totals]["OOH"]
    assert_empty summary["bu1"][:clients]
  end
end
