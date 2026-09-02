require "test_helper"
require "date"
require "time"
require "opsgenie_tools"

class StatsCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    @argv = ARGV.to_a
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["BUSINESS_UNIT_TAGS"] = "deliveryplus,govpress"
    ENV["TIME_TAGS"] = "OOH,inhours,wakinghours,sleepinghours"
    # Pin the date range explicitly so the baseline does not depend on
    # today's date, which Date.today - 7 otherwise would.
    ARGV.replace(%w[--start 2026-08-25 --end 2026-08-25])
  end

  def teardown
    ENV.replace(@env)
    ARGV.replace(@argv)
  end

  # --start/--end above become [2026-08-25, 2026-08-26) once the end date is
  # made exclusive.
  def expected_query
    OpsgenieTools::Query.created_between(Time.parse("2026-08-25"), Time.parse("2026-08-26"))
  end

  def test_output_is_unchanged
    stub_alerts_pages(fixture("alerts_stats"), [], query: expected_query)
    load_script("stats.rb")

    out, err = capture_io { main }

    assert_matches_baseline("stats", out)
    assert_equal "", err
  end
end
