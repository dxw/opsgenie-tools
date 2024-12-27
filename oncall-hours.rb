#!/usr/bin/env ruby
# script to work out how many hours each person was on call for a given payment month. Where we pay for the month the week of on call started in so first wednesday of the month to first wednesday of the next month.
# usage: PAYMENT_RATE=10.00 OPSGENIE_API_KEY=yourkeyhere OPSGENIE_SCHEDULE_ID=youridhere OPSGENIE_ROTATION_ID=youridhere bundle exec oncall-hours.rb
# you can also set OPSGENIE_DATE to a date in the month you want to calculate for, otherwise it will use the current date.
# These can all be set in a .env file in the same directory as the script as well
require 'dotenv'
require 'opsgenie'
require 'date'

Dotenv.load

Opsgenie.configure(api_key: ENV['OPSGENIE_API_KEY'])

def first_wednesday(year, month)
  day = Date.new(year, month, 1)
  day += 1 until day.wday == 3
  day.to_time + 10 * 60 * 60
end

def calculate_off_hours(start_time, end_time)
  (end_time - start_time) / 3600 # calculate hours difference
end

opsgenie_date = ENV['OPSGENIE_DATE'] ? Date.parse(ENV['OPSGENIE_DATE']) : DateTime.now
start_date = first_wednesday(opsgenie_date.year, opsgenie_date.month)
end_date = first_wednesday(opsgenie_date.next_month.year, opsgenie_date.next_month.month)

rotation_ids = ENV['OPSGENIE_ROTATION_ID'].split(',')

schedule = Opsgenie::Schedule.find_by_id(ENV['OPSGENIE_SCHEDULE_ID'])

timeline = schedule.timeline(date: start_date.to_date, interval: 2, interval_unit: :months)

total_hours = Hash.new(0)

timeline.each do |rotation|
  next unless rotation_ids.include?(rotation.id)
  rotation.periods.each do |period|
    next unless period.user

    period_start = [start_date, period.start_date.to_time].max
    period_end = [end_date, period.end_date.to_time].min

    next if period_end < start_date || period_start > end_date

    on_call_hours = calculate_off_hours(period_start, period_end)

    total_hours[period.user.full_name] += on_call_hours
  end
end

total_hours.each do |user_name, hours|
  payment = hours * ENV['PAYMENT_RATE'].to_f
  formatted_payment = sprintf('%.2f', payment)
  puts "#{user_name} was on call for #{hours} hours and should be paid £#{formatted_payment}."
end
