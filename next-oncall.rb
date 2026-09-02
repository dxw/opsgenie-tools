#!/usr/bin/env ruby
# script to find the next on-call period for a given user
# usage: next-oncall.rb -e <email>
# you should have the following environment variables set:
# OPSGENIE_API_KEY: your opsgenie api key
# OPSGENIE_SCHEDULE_ID: the id of the schedule you want to query
# OPSGENIE_ROTATION_ID: the id of the rotation you want to query
# LOOK_AHEAD_MONTHS: the number of months to look ahead for on-call periods (default: 6)
# you can also set these variables in a .env file in the same directory as this script
require 'date'
require 'dotenv'
require 'optparse'
require_relative 'lib/opsgenie_tools'

Dotenv.load

def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: next-oncall.rb [options]"

    opts.on("-e", "--email EMAIL", "Email") do |email|
      options[:email] = email
    end
  end.parse!

  raise OptionParser::MissingArgument, 'Email not provided' if options[:email].nil?

  interval = ENV.fetch('LOOK_AHEAD_MONTHS', 6).to_i
  rota = OpsgenieTools::Rota.new(ENV['OPSGENIE_API_KEY'])
  timeline = rota.timeline(ENV['OPSGENIE_SCHEDULE_ID'], from: Date.today, months: interval)

  rotation = timeline.find { |r| r.id == ENV['OPSGENIE_ROTATION_ID'] }
  next_on_call_period =
    if rotation
      OpsgenieTools::OnCall.next_period_for(rotation.periods,
                                            username: options[:email],
                                            after: DateTime.now)
    end

  if next_on_call_period
    # Format DateTime to be more human-readable
    formatted_date = next_on_call_period.start_date.strftime("%B %d, %Y")
    puts "#{options[:email]} is next on call on #{formatted_date}"
  else
    puts "#{options[:email]} is not on call in the next #{interval} months for the specified rotation."
  end
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
