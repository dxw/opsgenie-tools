#!/usr/bin/env ruby
# script to list all the schedules in OpsGenie and if passed a schedule name it will list the rotations for that schedule
# requires the OpsGenie API key to be set in the environment variable OPSGENIE_API_KEY
# usage: ./schedules.rb or ./schedules.rb -n <schedule_name>
require 'net/http'
require 'json'
require 'dotenv'
require 'optparse'

Dotenv.load

API_KEY = ENV['OPSGENIE_API_KEY']

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: schedules.rb [options] by default it will print all the schedules in OpsGenie"

  opts.on("-n", "--name SCHEDULE_NAME", "schedule name to find rotations for ") do |name|
    options[:schedule_name] = name
  end
end.parse!

def get_schedules(api_key)
  schedules = []
  limit = 100
  offset = 0
  loop do
    uri = URI("https://api.opsgenie.com/v2/schedules?limit=#{limit}&offset=#{offset}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "GenieKey #{api_key}"

    response = http.request(request)

    break if response.code.to_i != 200

    response_data = JSON.parse(response.body)
    schedules.concat(response_data['data'])

    break if response_data['paging'].nil? || response_data['paging']['next'].nil?

    offset += limit
  end

  schedules
end

def get_rotation_details(api_key, schedule_id)
  uri = URI("https://api.opsgenie.com/v2/schedules/#{schedule_id}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri.request_uri)
  request['Authorization'] = "GenieKey #{api_key}"

  response = http.request(request)

  if response.code.to_i == 200
    JSON.parse(response.body)
  else
    puts "Error: #{response.code} - #{response.message}"
    nil
  end
end

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

schedules = get_schedules(API_KEY)

if options[:schedule_name]
  schedule = schedules.find { |r| r['name'] == options[:schedule_name] }
  if schedule
    puts "Schedule ID for '#{options[:schedule_name]}' is '#{schedule['id']}'"
    rotation_details = get_rotation_details(API_KEY, schedule['id'])
    print_rotations(rotation_details['data']['rotations']) if rotation_details
  else
    puts "Rota '#{options[:schedule_name]}' not found"
  end
else
  print_all_schedules(schedules)
end
