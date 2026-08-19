#!/usr/bin/env ruby
# script to tag untagged alerts with a business unit tag
# requires the following environment variables:
#  OPSGENIE_API_KEY: API key for OpsGenie
#  TAGS_TO_EXCLUDE: comma-separated list of tags to exclude from the search
#  (e.g. TAGS_TO_EXCLUDE=tag1,tag2,tag3)
#  CLIENT_TO_BU_MAPPING: JSON string mapping client tags to business unit tags
#  (e.g. {"client_client1": "bu1", "client2": "bu2"} - the client_ prefix is optional)
#  CLIENT_TAG_MAPPING: optional, as used by client_tags.rb. Used to derive a
#  client tag from the alert message when the alert has no client_* tag
#  Note: the script will prompt for the tag to add to the alerts if no client match is
#  found, and will suggest CLIENT_TO_BU_MAPPING additions for anything tagged by hand

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

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
  end

  def alert_link(alert_id)
    "https://app.opsgenie.com/alert/detail/#{alert_id}"
  end
end

CLIENT_TAG_PREFIX = 'client_'

def prompt_for_tag(tags)
  puts 'Which tag would you like to add?'
  tags.each_with_index do |tag, index|
    puts "#{index + 1}. #{tag}"
  end
  print "Enter the number corresponding to the desired tag or action (Default is #{tags.first}): "
  tag_number = $stdin.gets.chomp.to_i
  tag_number.zero? ? tags.first : tags[tag_number - 1]
end

# keys may be given with or without the client_ prefix
def normalise_bu_mapping(mapping)
  mapping.each_with_object({}) do |(client, bu), normalised|
    key = client.downcase
    key = "#{CLIENT_TAG_PREFIX}#{key}" unless key.start_with?(CLIENT_TAG_PREFIX)
    normalised[key] = bu
  end
end

def client_tag_on_alert(alert)
  alert.fetch('tags', []).map(&:downcase).find do |tag|
    # ignore the bare 'client_' tag some alerts carry
    tag.start_with?(CLIENT_TAG_PREFIX) && tag.length > CLIENT_TAG_PREFIX.length
  end
end

def client_tag_from_message(message, client_tag_mapping)
  return nil if message.nil?

  _, tag = client_tag_mapping.find { |needle, _| message.downcase.include?(needle.downcase) }
  tag&.downcase
end

# suggestions: client tag => { bu => times chosen }
def report_suggestions(suggestions, bu_mapping)
  return if suggestions.empty?

  puts "\nSuggested CLIENT_TO_BU_MAPPING additions based on the tags you chose by hand:"
  additions = {}
  suggestions.each do |client_tag, counts|
    bu, = counts.max_by { |_, count| count }
    puts "  #{client_tag} => #{bu} (#{counts.map { |b, c| "#{b}: #{c}" }.join(', ')})"
    puts "  WARNING: #{client_tag} was tagged inconsistently, check before using" if counts.size > 1
    additions[client_tag] = bu
  end

  puts "\nCopy this into your .env to avoid the same prompts next time:"
  puts "CLIENT_TO_BU_MAPPING=#{bu_mapping.merge(additions).to_json}"
end

def report_untagged(untagged_alerts, opsgenie)
  return if untagged_alerts.empty?

  puts "\nSkipped #{untagged_alerts.length} alert(s):"
  untagged_alerts.each do |alert|
    client_tag = client_tag_on_alert(alert) || 'no client tag'
    puts "  #{opsgenie.alert_link(alert['id'])} (#{client_tag}) #{alert['message']}"
  end
  puts 'Alerts with no client tag can be tagged with client_tags.rb first.'
end

api_key = ENV['OPSGENIE_API_KEY']
tags_to_exclude = ENV['TAGS_TO_EXCLUDE'].split(',')
bu_mapping = normalise_bu_mapping(JSON.parse(ENV['CLIENT_TO_BU_MAPPING'] || '{}'))
client_tag_mapping = JSON.parse(ENV['CLIENT_TAG_MAPPING'] || '{}')

opsgenie = OpsGenie.new(api_key)

alerts = opsgenie.alerts_without_tags(tags_to_exclude)

untagged_alerts = []
suggestions = {}

if alerts.empty?
  puts 'No alerts found without the specified tags.'
else
  alerts.each do |alert|
    puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"

    # Prefer the alert's own client_* tag, then fall back to matching the
    # message against CLIENT_TAG_MAPPING as client_tags.rb does
    client_tag = client_tag_on_alert(alert)
    matched_bu = client_tag && bu_mapping[client_tag]

    if matched_bu
      puts "Matched client tag '#{client_tag}'."
    else
      message_tag = client_tag_from_message(alert['message'], client_tag_mapping)
      if message_tag && bu_mapping[message_tag]
        client_tag = message_tag
        matched_bu = bu_mapping[message_tag]
        puts "No usable client tag, matched '#{client_tag}' from the alert message."
      elsif client_tag
        puts "Client tag '#{client_tag}' is not in CLIENT_TO_BU_MAPPING."
      else
        client_tag = message_tag
        puts 'No client tag found for this alert.'
      end
    end

    if matched_bu
      response = opsgenie.add_tag_to_alert(alert['id'], matched_bu)
      if %w[200 202].include?(response.code)
        puts "Automatically added tag '#{matched_bu}' to alert '#{alert['id']}' based on client tag '#{client_tag}'."
      else
        puts "Error: Unable to add tag '#{matched_bu}' to alert '#{alert['id']}' (status code: #{response.code})"
      end
      next
    end

    # If no match, prompt the user
    new_tag = prompt_for_tag(tags_to_exclude + ['skip'])
    if new_tag == 'skip'
      untagged_alerts << alert
      next
    end
    response = opsgenie.add_tag_to_alert(alert['id'], new_tag)
    if %w[200 202].include?(response.code)
      puts "Added tag '#{new_tag}' to alert '#{alert['id']}'."
      if client_tag
        suggestions[client_tag] ||= {}
        suggestions[client_tag][new_tag] = suggestions[client_tag].fetch(new_tag, 0) + 1
      end
    else
      puts "Error: Unable to add tag '#{new_tag}' to alert '#{alert['id']}' (status code: #{response.code})"
    end
  end
end

report_suggestions(suggestions, bu_mapping)
report_untagged(untagged_alerts, opsgenie)
