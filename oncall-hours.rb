#!/usr/bin/env ruby
# script to work out how many hours each person was on call for a given payment month. Where we pay for the month the week of on call started in so first wednesday of the month to first wednesday of the next month.
# usage: PAYMENT_RATE=10.00 OPSGENIE_API_KEY=yourkeyhere OPSGENIE_SCHEDULE_ID=youridhere OPSGENIE_ROTATION_ID=youridhere bundle exec oncall-hours.rb
# you can also set OPSGENIE_DATE to a date in the month you want to calculate for, otherwise it will use the current date.
# These can all be set in a .env file in the same directory as the script as well
require 'date'
require 'dotenv'
require_relative 'lib/opsgenie_tools'

Dotenv.load

def main
  rate = ENV['PAYMENT_RATE'].to_f
  if rate.zero?
    puts 'Error: Please set PAYMENT_RATE to the hourly on-call rate.'
    exit 1
  end

  opsgenie_date = ENV['OPSGENIE_DATE'] ? Date.parse(ENV['OPSGENIE_DATE']) : DateTime.now
  start_date, end_date = OpsgenieTools::Payment.window_for(opsgenie_date)
  if ENV['DEBUG']
  puts "Calculating on call hours from #{start_date} to #{end_date}"
  end

  rotation_ids = ENV['OPSGENIE_ROTATION_ID'].to_s.split(',').map(&:strip).reject(&:empty?)
  if rotation_ids.empty?
    puts 'Error: Please set OPSGENIE_ROTATION_ID to the rotation ids to report on.'
    exit 1
  end
  rota = OpsgenieTools::Rota.new(ENV['OPSGENIE_API_KEY'])
  timeline = rota.timeline(ENV['OPSGENIE_SCHEDULE_ID'], from: start_date.to_date, months: 2)

  total_hours = Hash.new(0)

  timeline.each do |rotation|
    next unless rotation_ids.include?(rotation.id)

    rotation_totals = OpsgenieTools::Payment.totals(rotation.periods, window: [start_date, end_date])

    if ENV['DEBUG']
      rotation_totals.each do |user_name, hours|
        puts "#{user_name} was on call for #{hours} hours from #{start_date} to #{end_date} for rotation #{rotation.name}"
      end
    end

    rotation_totals.each { |user_name, hours| total_hours[user_name] += hours }
  end

  total_hours.each do |user_name, hours|
    formatted_payment = OpsgenieTools::Payment.payment_for(hours, rate)
    puts "#{user_name} was on call for #{hours} hours and should be paid £#{formatted_payment}."
  end
  if ENV['DEBUG']
  puts "Total hours: #{total_hours.values.sum}"
  puts "Total payment: £#{OpsgenieTools::Payment.payment_for(total_hours.values.sum, rate)}"
  end
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
