#!/usr/bin/env ruby
# script to tag untagged alerts with a business unit tag
# requires the following environment variables:
#  OPSGENIE_API_KEY: API key for OpsGenie
#  TAGS_TO_EXCLUDE: comma-separated list of tags to exclude from the search
#  (e.g. TAGS_TO_EXCLUDE=tag1,tag2,tag3)
#  Note: the script will prompt for the tag to add to the alerts

require 'net/http'
require 'json'
require 'dotenv'
require 'date'

Dotenv.load

class OpsGenie
  def initialize(api_key)
    @api_key = api_key
  end

  def alerts_without_tags(tags)
    query = "NOT (tags:#{tags.join(' OR tags:')})"
    date_threshold = (Date.today - 30).strftime('%d-%m-%Y')
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

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    response
  end

  def alert_link(alert_id)
    "https://app.opsgenie.com/alert/detail/#{alert_id}"
  end
end

def prompt_for_tag(tags)
  puts 'Which tag would you like to add?'
  tags.each_with_index do |tag, index|
    puts "#{index + 1}. #{tag}"
  end
  print "Enter the number corresponding to the desired tag or action (Default is #{tags.first}): "
  tag_number = gets.chomp.to_i
  tag_number.zero? ? tags.first : tags[tag_number - 1]
end

api_key = ENV['OPSGENIE_API_KEY']
tags_to_exclude = ENV['TAGS_TO_EXCLUDE'].split(',')
opsgenie = OpsGenie.new(api_key)

alerts = opsgenie.alerts_without_tags(tags_to_exclude)

untagged_alerts = []

if alerts.empty?
  puts 'No alerts found without the specified tags.'
else
  alerts.each do |alert|
    puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"
    new_tag = prompt_for_tag(tags_to_exclude + ['skip'])
    if new_tag == 'skip'
      untagged_alerts << alert
      next
    end
    response = opsgenie.add_tag_to_alert(alert['id'], new_tag)
    if response.code == '200' || response.code == '202'
      puts "Added tag '#{new_tag}' to alert '#{alert['id']}'."
    else
      puts "Error: Unable to add tag '#{new_tag}' to alert '#{alert['id']}' (status code: #{response.code})"
    end
  end
end
