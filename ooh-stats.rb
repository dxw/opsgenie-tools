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

# Estimate monthly TOIL from acknowledged OOH alerts, mirroring calculate-toil.rb:
# sleepinghours-tagged alerts use sleeping_rate, wakinghours use waking_rate.
# Per user and category, alerts within 1800s of the previous counted one are
# treated as duplicates and skipped.
def monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate)
  toil_by_month = Hash.new(0.0)
  # last_counted[user][category] = Time
  last_counted = Hash.new { |h, k| h[k] = Hash.new(Time.at(0)) }

  ordered = alerts.sort_by { |a| Time.parse(a["createdAt"]) }
  ordered.each do |alert|
    next unless alert["acknowledged"]
    tags = alert["tags"] || []
    category, rate =
      if tags.include?("sleepinghours")
        ["sleepinghours", sleeping_rate]
      elsif tags.include?("wakinghours")
        ["wakinghours", waking_rate]
      end
    next if category.nil?

    user = alert.dig("report", "acknowledgedBy")
    created = Time.parse(alert["createdAt"])
    next unless (created - last_counted[user][category]) > 1800

    last_counted[user][category] = created
    toil_by_month[created.strftime("%Y-%m")] += rate
  end

  month_windows(start_date, end_date).map do |window_start, _window_end|
    key = window_start.strftime("%Y-%m")
    [key, toil_by_month[key]]
  end
end

# Fetch all OOH-tagged alerts in [start_date, end_date), one month per query
# window to stay under OpsGenie's offset+limit <= 20000 ceiling.
def fetch_ooh_alerts(api_key, start_date, end_date)
  all_alerts = []
  month_windows(start_date, end_date).each do |window_start, window_end|
    offset = 0
    loop do
      formatted_start = Time.parse(window_start.to_s).strftime("%d-%m-%YT%H:%M:%S")
      formatted_end   = Time.parse(window_end.to_s).strftime("%d-%m-%YT%H:%M:%S")
      query = "createdAt >= '#{formatted_start}' AND createdAt < '#{formatted_end}' AND tags:(OOH)"
      url = "#{BASE_URL}?limit=#{LIMIT}&offset=#{offset}&query=#{URI.encode_www_form_component(query)}"
      response = HTTParty.get(url, headers: {
        "Authorization" => "GenieKey #{api_key}",
        "Content-Type"  => "application/json"
      })
      if response.code != 200
        puts "Error fetching alerts: #{response.body}"
        exit 1
      end
      alerts = JSON.parse(response.body)["data"] || []
      break if alerts.empty?
      all_alerts.concat(alerts)
      offset += LIMIT
    end
  end
  all_alerts
end

if __FILE__ == $0
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
  alerts = fetch_ooh_alerts(api_key, start_date, end_date)
  puts "Fetched #{alerts.size} OOH alerts."

  CSV.open("ooh_daily_counts.csv", "w") do |csv|
    csv << ["date", "count"]
    daily_counts(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_totals.csv", "w") do |csv|
    csv << ["month", "count"]
    monthly_totals(alerts, start_date, end_date).each { |row| csv << row }
  end

  CSV.open("ooh_monthly_toil.csv", "w") do |csv|
    csv << ["month", "toil_hours"]
    monthly_toil(alerts, start_date, end_date, sleeping_rate, waking_rate).each { |row| csv << row }
  end

  puts "Wrote ooh_daily_counts.csv, ooh_monthly_totals.csv, ooh_monthly_toil.csv"
end
