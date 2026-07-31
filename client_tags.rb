#!/usr/bin/env ruby
# script to tag untagged alerts with a client tag
# requires the following environment variables:
#  OPSGENIE_API_KEY: API key for OpsGenie
#  CLIENT_TAG_MAPPING: JSON string mapping strings found in an alert message to
#  client tags (e.g. {"dalmatian": "client_dalmatian", "caselaw": "client_moj"})
#  Note: the script will prompt for the tag to add to the alerts if no client
#  match is found

require 'net/http'
require 'json'
require 'dotenv'
require 'date'

Dotenv.load

class OpsGenie
  def initialize(api_key)
    @api_key = api_key
  end

  def alerts_without_client_tags(days)
    query = "NOT tags:client_*"
    date_threshold = (Date.today - days).strftime('%d-%m-%Y')
    query += " AND createdAt>#{date_threshold}"
    all_alerts = []
    offset = 0
    limit = 100

    loop do
      uri = URI("https://api.opsgenie.com/v2/alerts?query=#{URI.encode_www_form_component(query)}&limit=#{limit}&offset=#{offset}")

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "GenieKey #{@api_key}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(request)
      end

      if response.code == '200'
        alerts = JSON.parse(response.body)['data']
        all_alerts += alerts
        break if alerts.length < limit

        offset += limit
      else
        puts "Error: Unable to fetch alerts from OpsGenie (status code: #{response.code})"
        break
      end
    end

    all_alerts
  end

  def add_tag_to_alert(alert_id, tag)
    uri = URI("https://api.opsgenie.com/v2/alerts/#{alert_id}/tags")

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "GenieKey #{@api_key}"
    request['Content-Type'] = 'application/json'
    request.body = { tags: [tag] }.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
  end

  def alert_link(alert_id)
    "https://app.opsgenie.com/alert/detail/#{alert_id}"
  end
end

def prompt_for_client_tag
  print 'Enter client name for the tag (client_$clientname), or leave blank to skip: '
  client_name = $stdin.gets.chomp
  return 'skip' if client_name.empty?

  "client_#{client_name}"
end

days = ARGV[0] ? ARGV[0].to_i : 30
api_key = ENV['OPSGENIE_API_KEY']
client_tag_mapping = JSON.parse(ENV['CLIENT_TAG_MAPPING'] || '{}')

opsgenie = OpsGenie.new(api_key)

puts "Looking for alerts without a client tag from the last #{days} days..."
alerts = opsgenie.alerts_without_client_tags(days)

untagged_alerts = []

if alerts.empty?
  puts 'No alerts found without a client tag.'
else
  alerts.each do |alert|
    puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"

    # Try to automatically tag based on client name in the message
    matched_tag = nil
    client_tag_mapping.each do |needle, tag|
      if alert['message'].downcase.include?(needle.downcase)
        matched_tag = tag
        break
      end
    end

    if matched_tag
      response = opsgenie.add_tag_to_alert(alert['id'], matched_tag)
      if %w[200 202].include?(response.code)
        puts "Automatically added tag '#{matched_tag}' to alert '#{alert['id']}' based on client name."
      else
        puts "Error: Unable to add tag '#{matched_tag}' to alert '#{alert['id']}' (status code: #{response.code})"
      end
      next
    end

    # If no match, prompt the user
    new_tag = prompt_for_client_tag
    if new_tag == 'skip'
      untagged_alerts << alert
      next
    end
    response = opsgenie.add_tag_to_alert(alert['id'], new_tag)
    if %w[200 202].include?(response.code)
      puts "Added tag '#{new_tag}' to alert '#{alert['id']}'."
    else
      puts "Error: Unable to add tag '#{new_tag}' to alert '#{alert['id']}' (status code: #{response.code})"
    end
  end
end
