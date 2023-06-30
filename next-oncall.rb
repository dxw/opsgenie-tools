#!/usr/bin/env ruby
# script to find the next on-call period for a given user
# usage: next-oncall.rb -e <email>
# you should have the following environment variables set:
# OPSGENIE_API_KEY: your opsgenie api key
# OPSGENIE_SCHEDULE_ID: the id of the schedule you want to query
# OPSGENIE_ROTATION_ID: the id of the rotation you want to query
# LOOK_AHEAD_MONTHS: the number of months to look ahead for on-call periods (default: 6)
# you can also set these variables in a .env file in the same directory as this script

require 'date':
require 'opsgenie'
require 'dotenv'
require 'optparse'

# Load environment variables
Dotenv.load

# Configure Opsgenie
Opsgenie.configure(api_key: ENV['OPSGENIE_API_KEY'])

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: next-oncall.rb [options]"

  opts.on("-e", "--email EMAIL", "Email") do |email|
    options[:email] = email
  end
end.parse!

raise OptionParser::MissingArgument, 'Email not provided' if options[:email].nil?

# Fetch a schedule by its id
schedule = Opsgenie::Schedule.find_by_id(ENV['OPSGENIE_SCHEDULE_ID'])

# Fetch the schedule timeline for the next 'interval' months or default to 6
interval = ENV.fetch('LOOK_AHEAD_MONTHS', 6).to_i
timeline = schedule.timeline(interval: interval, interval_unit: :months)

next_on_call_period = nil

# Find rotation by id
rotation = timeline.find { |rotation| rotation.id == ENV['OPSGENIE_ROTATION_ID'] }

if rotation
  rotation.periods.each do |period|
    if period.user && period.user.username == options[:email] && period.start_date > DateTime.now
      next_on_call_period = period if next_on_call_period.nil? || period.start_date < next_on_call_period.start_date
    end
  end
end

if next_on_call_period
  # Format DateTime to be more human-readable
  formatted_date = next_on_call_period.start_date.strftime("%B %d, %Y")
  puts "#{options[:email]} is next on call on #{formatted_date}"
else
  puts "#{options[:email]} is not on call in the next #{interval} months for the specified rotation."
end
