#!/usr/bin/env ruby
# script to get the on call person for the next 4 weeks
require 'opsgenie'
require 'date'
require 'dotenv/load'

Opsgenie.configure(api_key: ENV['OPSGENIE_API_KEY'])

def next_wednesday
  today = Date.today
  days_until_wednesday = (3 - today.wday) % 7
  today + days_until_wednesday
end

# Fetch the schedule by its ID
schedule = Opsgenie::Schedule.find_by_id(ENV['OPSGENIE_SCHEDULE_ID'])

4.times do |i|
  wednesday = next_wednesday + i*7
  puts "On call for week starting #{wednesday.strftime('%Y-%m-%d')}:"
  
  date_time = DateTime.parse("#{wednesday.strftime('%Y-%m-%d')}T19:00:00")
  on_calls = schedule.on_calls(date_time)
  
  if on_calls.empty?
    puts "Nobody"
  else
    on_calls.each do |user|
      puts "#{user.full_name}"
    end
  end
end
