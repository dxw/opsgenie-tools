#!/usr/bin/env ruby
# Generate CSV stats for OpsGenie alerts tagged OOH over the past N years.
# Produces three CSVs in the current directory:
#   ooh_daily_counts.csv   (date,count)   - one row per calendar day
#   ooh_monthly_totals.csv (month,count)  - one row per month
#   ooh_monthly_toil.csv   (month,toil_hours) - monthly TOIL estimate
#
# Environment variables (may be set in a .env file):
#   OPSGENIE_API_KEY    required
#   TOIL_SLEEPING_HOURS TOIL per de-duped acknowledged sleepinghours alert (default 0.0)
#   TOIL_WAKING_HOURS   TOIL per de-duped acknowledged wakinghours alert (default 0.0)
#   YEARS_BACK          how many years back to look (default 3)
require 'dotenv/load'
require 'httparty'
require 'json'
require 'csv'
require 'date'
require 'time'
require 'uri'

BASE_URL = "https://api.opsgenie.com/v2/alerts"
LIMIT = 100

# Build [start, next] Date pairs, one per calendar month spanned by the range.
# The first pair starts at start_date; the last pair ends at end_date.
def month_windows(start_date, end_date)
  windows = []
  cursor = start_date
  while cursor < end_date
    first_of_next = if cursor.month == 12
                      Date.new(cursor.year + 1, 1, 1)
                    else
                      Date.new(cursor.year, cursor.month + 1, 1)
                    end
    window_end = [first_of_next, end_date].min
    windows << [cursor, window_end]
    cursor = first_of_next
  end
  windows
end

# Count alerts per calendar day, emitting a row for every day in the range
# (inclusive of days with zero alerts).
def daily_counts(alerts, start_date, end_date)
  counts = Hash.new(0)
  alerts.each do |alert|
    day = Time.parse(alert["createdAt"]).strftime("%Y-%m-%d")
    counts[day] += 1
  end

  rows = []
  day = start_date
  while day < end_date
    key = day.strftime("%Y-%m-%d")
    rows << [key, counts[key]]
    day += 1
  end
  rows
end

# Count alerts per calendar month, one row per month in the range.
def monthly_totals(alerts, start_date, end_date)
  counts = Hash.new(0)
  alerts.each do |alert|
    month = Time.parse(alert["createdAt"]).strftime("%Y-%m")
    counts[month] += 1
  end

  month_windows(start_date, end_date).map do |window_start, _window_end|
    key = window_start.strftime("%Y-%m")
    [key, counts[key]]
  end
end
