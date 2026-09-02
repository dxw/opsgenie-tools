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
require 'date'
require 'time'
require_relative 'lib/opsgenie_tools'

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

def main
  api_key = ENV['OPSGENIE_API_KEY']
  unless api_key
    puts "Error: Please set the OPSGENIE_API_KEY environment variable."
    exit 1
  end

  business_units = (ENV['BUSINESS_UNIT_TAGS'] || "deliveryplus,govpress").split(',').map(&:strip)
  time_tags = (ENV['TIME_TAGS'] || "OOH,inhours,wakinghours,sleepinghours").split(',').map(&:strip)

  options = parse_options
  start_date, end_date = determine_date_range(options)
  # Convert dates to Time objects (using midnight for each day).
  start_time = Time.parse(start_date.to_s)
  end_time   = Time.parse(end_date.to_s)

  # Format times for display.
  formatted_start = OpsgenieTools::Query.timestamp(start_time)
  formatted_end   = OpsgenieTools::Query.timestamp(end_time)
  puts "Fetching alerts from #{formatted_start} to #{formatted_end}..."

  query = OpsgenieTools::Query.created_between(start_time, end_time)
  alerts = OpsgenieTools::Client.new(api_key).alerts(query)
  summary = OpsgenieTools::Stats.summarise(alerts, business_units: business_units, time_tags: time_tags)

  total_alerts = alerts.size
  puts "\nTotal alerts processed: #{total_alerts}"
  output_summary(summary, time_tags, business_units)
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
