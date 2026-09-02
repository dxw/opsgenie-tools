#!/usr/bin/env ruby
# script to list all the schedules in OpsGenie and if passed a schedule name it will list the rotations for that schedule
# requires the OpsGenie API key to be set in the environment variable OPSGENIE_API_KEY
# usage: ./schedules.rb or ./schedules.rb -n <schedule_name>
require 'dotenv'
require 'optparse'
require_relative 'lib/opsgenie_tools'

Dotenv.load

def print_all_schedules(schedules)
  puts "All Schedules:"
  schedules.each do |schedule|
    puts "  #{schedule['name']} (ID: #{schedule['id']})"
  end
end

def print_rotations(rotations)
  puts "Rotations:"
  rotations.each do |rotation|
    puts "  #{rotation['name']} (ID: #{rotation['id']})"
  end
end

def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: schedules.rb [options] by default it will print all the schedules in OpsGenie"

    opts.on("-n", "--name SCHEDULE_NAME", "schedule name to find rotations for ") do |name|
      options[:schedule_name] = name
    end
  end.parse!

  client = OpsgenieTools::Client.new(ENV['OPSGENIE_API_KEY'])
  schedules = client.schedules

  if options[:schedule_name]
    schedule = schedules.find { |r| r['name'] == options[:schedule_name] }
    if schedule
      puts "Schedule ID for '#{options[:schedule_name]}' is '#{schedule['id']}'"
      print_rotations(client.schedule(schedule['id'])['rotations'] || [])
    else
      puts "Rota '#{options[:schedule_name]}' not found"
    end
  else
    print_all_schedules(schedules)
  end
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
