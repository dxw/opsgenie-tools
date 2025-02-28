#!/usr/bin/env ruby
# script to get the on call person for the next 4 weeks
require 'opsgenie'
require 'json'
require 'date'
require 'dotenv/load'

Opsgenie.configure(api_key: ENV['OPSGENIE_API_KEY'])

def next_wednesday
  today = Date.today
  days_until_wednesday = (3 - today.wday) % 7
  today + days_until_wednesday
end

def get_slack_name(email, email_to_slack_map)
  email_to_slack_map[email] || "Unknown"
end
# set weeks to 4 by default if OPSGENIE_WEEKS is not set
weeks = ENV['OPSGENIE_WEEKS'] || 4
# make sure weeks is an integer
weeks = weeks.to_i
# Fetch the schedule by its ID
schedule = Opsgenie::Schedule.find_by_id(ENV['OPSGENIE_SCHEDULE_ID'])
secondline_schedule = Opsgenie::Schedule.find_by_id(ENV['OPSGENIE_SCHEDULE_ID_SECONDLINE'])

# Parse the email to Slack username map from the environment variable
email_to_slack_map = JSON.parse(ENV['EMAIL_TO_SLACK_MAP'])
puts "Week starting: 1st line / 2nd line"
weeks.times do |i|
  wednesday = next_wednesday + i*7
 # puts "On call for week starting #{wednesday.strftime('%Y-%m-%d')}:"
  date_time = DateTime.parse("#{wednesday.strftime('%Y-%m-%d')}T19:00:00")
  on_calls = schedule.on_calls(date_time)
  secondline_on_calls = secondline_schedule.on_calls(date_time)
  if on_calls.empty?
    #puts "1st Line: Nobody"
  else
    on_calls.each do |user|
      $slack_name = get_slack_name(user.username, email_to_slack_map)
    #  puts "1st Line: @#{slack_name}"
    end
  end
  if secondline_on_calls.empty?
    #puts "2nd Line: Nobody"
  else
    secondline_on_calls.each do |user|
      $second_slack_name = get_slack_name(user.username, email_to_slack_map)
     # puts "2nd Line: @#{second_slack_name}"
     # puts ""
    end
  end
  puts "#{wednesday.strftime('%Y-%m-%d')}: @#{$slack_name} / @#{$second_slack_name}"
end
