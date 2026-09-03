require "test_helper"
require "opsgenie_tools"
require "date"

class PaymentTest < Minitest::Test
  P = OpsgenieTools::Payment

  Period = Struct.new(:start_date, :end_date, :user)
  User = Struct.new(:full_name)

  def test_window_runs_first_wednesday_to_first_wednesday
    from, to = P.window_for(Date.new(2026, 9, 10))

    assert_equal "2026-09-02 10:00", from.strftime("%Y-%m-%d %H:%M")
    assert_equal "2026-10-07 10:00", to.strftime("%Y-%m-%d %H:%M")
  end

  def test_window_when_the_month_starts_on_a_wednesday
    from, = P.window_for(Date.new(2026, 7, 15))

    assert_equal "2026-07-01 10:00", from.strftime("%Y-%m-%d %H:%M")
  end

  def test_window_across_a_year_boundary
    from, to = P.window_for(Date.new(2026, 12, 20))

    assert_equal "2026-12-02 10:00", from.strftime("%Y-%m-%d %H:%M")
    assert_equal "2027-01-06 10:00", to.strftime("%Y-%m-%d %H:%M")
  end

  # Requiring this file alone must not raise: reaching into a sibling module
  # for a weekday made window_for fail with NameError.
  def test_the_module_works_without_its_siblings_loaded
    output = IO.popen(["ruby", "-I#{File.join(ROOT, "lib")}", "-rdate", "-e",
                       'require "opsgenie_tools/payment"; ' \
                       'print OpsgenieTools::Payment.window_for(Date.new(2026, 9, 10)).first.strftime("%Y-%m-%d")'],
                      err: %i[child out], &:read)

    assert_predicate $?, :success?, "requiring payment.rb alone failed:\n#{output}"
    assert_equal "2026-09-02", output
  end

  def test_hours_between
    assert_equal 168.0, P.hours_between(Time.utc(2026, 9, 2, 10), Time.utc(2026, 9, 9, 10))
  end

  def test_totals_sums_per_person_and_clamps_to_the_window
    window = [Time.utc(2026, 9, 2, 10), Time.utc(2026, 9, 9, 10)]
    periods = [
      Period.new(Time.utc(2026, 9, 2, 10), Time.utc(2026, 9, 9, 10), User.new("First Example")),
      # starts before the window, so only the part inside it counts
      Period.new(Time.utc(2026, 8, 26, 10), Time.utc(2026, 9, 3, 10), User.new("Second Example"))
    ]

    totals = P.totals(periods, window: window)

    assert_equal 168.0, totals["First Example"]
    assert_equal 24.0, totals["Second Example"]
  end

  def test_totals_skips_periods_with_no_user_and_periods_outside_the_window
    window = [Time.utc(2026, 9, 2, 10), Time.utc(2026, 9, 9, 10)]
    periods = [
      Period.new(Time.utc(2026, 9, 2, 10), Time.utc(2026, 9, 9, 10), nil),
      Period.new(Time.utc(2026, 7, 1, 10), Time.utc(2026, 7, 8, 10), User.new("Second Example"))
    ]

    assert_empty P.totals(periods, window: window)
  end

  def test_payment_for
    assert_equal "1680.00", P.payment_for(168.0, 10.0)
    assert_equal "0.00", P.payment_for(0, 10.0)
  end
end
