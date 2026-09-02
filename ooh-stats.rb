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
require 'csv'
require 'date'
require 'time'
require_relative 'lib/opsgenie_tools'

# Estimate monthly TOIL from acknowledged OOH alerts, via OpsgenieTools::Toil.
def monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate)
  by_month = OpsgenieTools::Toil.by_month(alerts, sleeping: sleeping_rate, waking: waking_rate)

  OpsgenieTools::Stats.month_windows(start_date, end_date).map do |window_start, _window_end|
    key = window_start.strftime("%Y-%m")
    [key, by_month.fetch(key, 0.0)]
  end
end

# Fetch all OOH-tagged alerts in [start_date, end_date), one month per query
# window to stay under OpsGenie's offset+limit <= 20000 ceiling.
def fetch_ooh_alerts(client, start_date, end_date)
  OpsgenieTools::Stats.month_windows(start_date, end_date).flat_map do |window_start, window_end|
    client.alerts(OpsgenieTools::Query.created_between(
                    Time.parse(window_start.to_s), Time.parse(window_end.to_s), tags: %w[OOH]
                  ))
  end
end

def main
  api_key = ENV['OPSGENIE_API_KEY']
  unless api_key
    puts "Error: Please set the OPSGENIE_API_KEY environment variable."
    exit 1
  end

  sleeping_rate = ENV['TOIL_SLEEPING_HOURS'] ? ENV['TOIL_SLEEPING_HOURS'].to_f : 0.0
  waking_rate   = ENV['TOIL_WAKING_HOURS'] ? ENV['TOIL_WAKING_HOURS'].to_f : 0.0
  years_back    = ENV['YEARS_BACK'] ? ENV['YEARS_BACK'].to_i : 3

  end_date   = Date.today + 1
  start_date = end_date.prev_year(years_back)

  puts "Fetching OOH alerts from #{start_date} to #{end_date}..."
  alerts = fetch_ooh_alerts(OpsgenieTools::Client.new(api_key), start_date, end_date)
  puts "Fetched #{alerts.size} OOH alerts."

  CSV.open("ooh_daily_counts.csv", "w") do |csv|
    csv << ["date", "count"]
    OpsgenieTools::Stats.daily_counts(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_totals.csv", "w") do |csv|
    csv << ["month", "count"]
    OpsgenieTools::Stats.monthly_totals(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_toil.csv", "w") do |csv|
    csv << ["month", "toil_hours"]
    monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate).each { |row| csv << row }
  end

  puts "Wrote ooh_daily_counts.csv, ooh_monthly_totals.csv, ooh_monthly_toil.csv"
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
