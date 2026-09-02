require "test_helper"
require "tmpdir"
require "date"
require "minitest/mock"

# ooh-stats.rb derives its month windows from Date.today and has no --start
# option, so the clock is frozen to keep the baselines stable across days.
FROZEN_TODAY = Date.new(2026, 9, 2).freeze

# ooh-stats.rb issues one created_between query per month window (13 of
# them here), each with a different timestamp pair, so no single exact
# string will do. This pins the shape Query.created_between(..., tags:
# %w[OOH]) produces and, critically, the trailing "AND tags:(OOH)" clause -
# exactly what M3 (fetch_ooh_alerts dropping tags: %w[OOH]) would omit.
TIMESTAMP = /\d{2}-\d{2}-\d{4}T\d{2}:\d{2}:\d{2}/
OOH_QUERY_SHAPE = /\AcreatedAt >= '#{TIMESTAMP}' AND createdAt < '#{TIMESTAMP}' AND tags:\(OOH\)\z/

class OohStatsCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["TOIL_SLEEPING_HOURS"] = "0.5"
    ENV["TOIL_WAKING_HOURS"] = "0.25"
    ENV["YEARS_BACK"] = "1"
  end

  def teardown
    ENV.replace(@env)
  end

  # ooh-stats.rb writes three CSVs and prints a handful of summary lines.
  # Task 8 moves the code behind all four out of this script and into the
  # library, so all four need a baseline, not just one CSV.
  def test_output_is_unchanged
    stub_alerts_pages(fixture("alerts_toil_week"), [], query: OOH_QUERY_SHAPE)
    load_script("ooh-stats.rb")

    out = err = nil
    daily_counts = monthly_totals = monthly_toil = nil

    Date.stub(:today, FROZEN_TODAY) do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { out, err = capture_io { main } }

        daily_counts   = File.read(File.join(dir, "ooh_daily_counts.csv"))
        monthly_totals = File.read(File.join(dir, "ooh_monthly_totals.csv"))
        monthly_toil   = File.read(File.join(dir, "ooh_monthly_toil.csv"))
      end
    end

    # assert_matches_baseline calls `skip` as soon as UPDATE_BASELINES is
    # set, which would abort this method after the first of the four
    # baselines below. Write them all in one pass instead, then skip once,
    # so a single UPDATE_BASELINES=1 run regenerates the lot.
    if ENV["UPDATE_BASELINES"]
      write_baseline("ooh-stats-stdout", out)
      write_baseline("ooh-stats-daily-counts", daily_counts)
      write_baseline("ooh-stats-monthly-totals", monthly_totals)
      write_baseline("ooh-stats-monthly-toil", monthly_toil)
      skip "wrote ooh-stats baselines"
    end

    assert_matches_baseline("ooh-stats-stdout", out)
    assert_equal "", err
    assert_matches_baseline("ooh-stats-daily-counts", daily_counts)
    assert_matches_baseline("ooh-stats-monthly-totals", monthly_totals)
    assert_matches_baseline("ooh-stats-monthly-toil", monthly_toil)
  end

  private

  def write_baseline(name, content)
    path = baseline(name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
