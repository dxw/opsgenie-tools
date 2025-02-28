#!/usr/bin/env ruby
# script to generate stats for alerts in Opsgenie
# Usage: ruby stats.rb [options]
# Options:
#
#   --last-week: Show stats for the last 7 days
#   --last-month: Show stats for the last full month
#   --start DATE: Start date (YYYY-MM-DD)
#   --end DATE: End date (YYYY-MM-DD)
#   -h, --help: Show help
#
#   The script requires the following environment variables to be set:
#   OPSGENIE_API_KEY: The API key for Opsgenie
#   BUSINESS_UNIT_TAGS: Comma-separated list of business unit tags
#   TIME_TAGS: Comma-separated list of time tags
#   Example:
#   OPSGENIE_API_KEY=your-api-key
#   BUSINESS_UNIT_TAGS=unit1,unit2
#   TIME_TAGS=OOH,inhours,wakinghours,sleepinghours
#   
#   These can be set in a .env file in the same directory as the script.
require 'dotenv/load'
require 'optparse'
require 'httparty'
require 'json'
require 'date'
require 'time'
require 'uri'

# Ensure the Opsgenie API key is available as an environment variable.
OPSGENIE_API_KEY = ENV['OPSGENIE_API_KEY']
unless OPSGENIE_API_KEY
  puts "Error: Please set the OPSGENIE_API_KEY environment variable."
  exit 1
end

BASE_URL = "https://api.opsgenie.com/v2/alerts"
LIMIT = 100

# Parse command-line options.
def parse_options
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby stats.rb [options]"
    opts.on("--last-week", "Show stats for the last 7 days") do
      options[:range] = :last_week
    end
    opts.on("--last-month", "Show stats for the last full month") do
      options[:range] = :last_month
    end
    opts.on("--start DATE", "Start date (YYYY-MM-DD)") do |date|
      options[:start_date] = Date.parse(date) rescue nil
    end
    opts.on("--end DATE", "End date (YYYY-MM-DD)") do |date|
      options[:end_date] = Date.parse(date) rescue nil
    end
    opts.on("-h", "--help", "Show help") do
      puts opts
      exit
    end
  end.parse!
  options
end

# Determine the date range based on the options.
def determine_date_range(options)
  case options[:range]
  when :last_week
    start_date = Date.today - 7
    end_date   = Date.today
    return start_date, end_date
  when :last_month
    today = Date.today
    first_day_this_month = Date.new(today.year, today.month, 1)
    last_month_end = first_day_this_month - 1
    last_month_start = Date.new(last_month_end.year, last_month_end.month, 1)
    return last_month_start, last_month_end + 1
  else
    if options[:start_date] && options[:end_date]
      return options[:start_date], options[:end_date] + 1
    else
      start_date = Date.today - 7
      return start_date, Date.today
    end
  end
end

# Fetch alerts from Opsgenie in the given time range using pagination.
def fetch_alerts(start_time, end_time)
  all_alerts = []
  offset = 0
  loop do
    # Format times as "dd-MM-yyyy'T'HH:mm:ss" per Opsgenie requirements.
    formatted_start = start_time.strftime("%d-%m-%YT%H:%M:%S")
    formatted_end   = end_time.strftime("%d-%m-%YT%H:%M:%S")
    query = "createdAt >= '#{formatted_start}' AND createdAt < '#{formatted_end}'"
    url = "#{BASE_URL}?limit=#{LIMIT}&offset=#{offset}&query=#{URI.encode_www_form_component(query)}"
    response = HTTParty.get(url, headers: {
      "Authorization" => "GenieKey #{OPSGENIE_API_KEY}",
      "Content-Type"  => "application/json"
    })
    if response.code != 200
      puts "Error fetching alerts: #{response.body}"
      exit 1
    end
    data = JSON.parse(response.body)
    alerts = data["data"] || []
    break if alerts.empty?
    all_alerts.concat(alerts)
    offset += LIMIT
  end
  all_alerts
end

# Process alerts to create a summary report.
#
# For each alert that has a business unit tag (from env var BUSINESS_UNIT_TAGS),
# we count any matching time tags (from env var TIME_TAGS). Additionally, if the alert
# has client tags (starting with "client_"), we count them for that business unit.
#
# The summary includes overall company totals, per–business unit totals,
# and client breakdowns per business unit.
def process_alerts(alerts)
  # Get configurable tags from env variables.
  business_units = (ENV['BUSINESS_UNIT_TAGS'] || "deliveryplus,govpress").split(',').map(&:strip)
  time_tags = (ENV['TIME_TAGS'] || "OOH,inhours,wakinghours,sleepinghours").split(',').map(&:strip)

  # Initialize the summary.
  summary = { "company" => { totals: Hash.new(0) } }
  business_units.each do |bu|
    summary[bu] = { totals: Hash.new(0), clients: {} }
  end

  alerts.each do |alert|
    tags = alert["tags"] || []
    # Identify the business unit for this alert (first match).
    bu = business_units.find { |b| tags.include?(b) }
    next if bu.nil?

    present_time_tags = tags & time_tags
    next if present_time_tags.empty?

    # Update totals for both the business unit and company.
    present_time_tags.each do |ttag|
      summary[bu][:totals][ttag] += 1
      summary["company"][:totals][ttag] += 1
    end

    # Update client-specific counts.
    client_tags = tags.select { |t| t.start_with?("client_") }
    client_tags.each do |ctag|
      client_name = ctag.sub(/^client_/, '')
      summary[bu][:clients][client_name] ||= Hash.new(0)
      present_time_tags.each do |ttag|
        summary[bu][:clients][client_name][ttag] += 1
      end
    end
  end

  return summary, business_units, time_tags
end

# Output the summary report.
def output_summary(summary, time_tags, business_units)
  puts "\n=== Company Totals ==="
  company_totals = summary["company"][:totals]
  time_tags.each do |tag|
    puts "  #{tag}: #{company_totals[tag]}"
  end

  business_units.each do |bu|
    puts "\n=== Business Unit: #{bu} ==="
    bu_data = summary[bu]
    puts "  Overall Totals:"
    time_tags.each do |tag|
      puts "    #{tag}: #{bu_data[:totals][tag]}"
    end

    if bu_data[:clients].empty?
      puts "  No client-specific alerts found."
    else
      puts "  By Client:"
      bu_data[:clients].each do |client, counts|
        puts "    Client: #{client}"
        time_tags.each do |tag|
          puts "      #{tag}: #{counts[tag]}"
        end
      end
    end
  end
end

if __FILE__ == $0
  options = parse_options
  start_date, end_date = determine_date_range(options)
  # Convert dates to Time objects (using midnight for each day).
  start_time = Time.parse(start_date.to_s)
  end_time   = Time.parse(end_date.to_s)
  
  # Format times for display.
  formatted_start = start_time.strftime("%d-%m-%YT%H:%M:%S")
  formatted_end   = end_time.strftime("%d-%m-%YT%H:%M:%S")
  puts "Fetching alerts from #{formatted_start} to #{formatted_end}..."
  
  alerts = fetch_alerts(start_time, end_time)
  summary, business_units, time_tags = process_alerts(alerts)
  
  total_alerts = alerts.size
  puts "\nTotal alerts processed: #{total_alerts}"
  output_summary(summary, time_tags, business_units)
end
