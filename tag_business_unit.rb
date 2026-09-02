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

require "json"
require "dotenv"
require "date"
require_relative "lib/opsgenie_tools"

Dotenv.load

def prompt_for_tag(tags, input: $stdin)
  puts 'Which tag would you like to add?'
  tags.each_with_index do |tag, index|
    puts "#{index + 1}. #{tag}"
  end

  loop do
    print "Enter the number corresponding to the desired tag or action (Default is #{tags.first}): "
    answer = input.gets
    # nil means stdin is at EOF. Pressing enter selects the default tag, but at
    # EOF nobody chose it, so skip rather than tag every remaining alert with it
    return 'skip' if answer.nil?

    choice = answer.chomp.to_i
    return tags.first if choice.zero?
    return tags[choice - 1] if choice.between?(1, tags.length)

    # an out of range answer used to return nil, which reached the API as a
    # request to add no tag at all
    puts "There is no option #{choice}."
  end
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

def report_untagged(untagged_alerts, client)
  return if untagged_alerts.empty?

  puts "\nSkipped #{untagged_alerts.length} alert(s):"
  untagged_alerts.each do |alert|
    client_tag = OpsgenieTools::Tagging.client_tag_on_alert(alert) || 'no client tag'
    puts "  #{client.alert_link(alert['id'])} (#{client_tag}) #{alert['message']}"
  end
  puts 'Alerts with no client tag can be tagged with client_tags.rb first.'
end

def main
  api_key = ENV['OPSGENIE_API_KEY']
  tags_to_exclude = ENV['TAGS_TO_EXCLUDE'].to_s.split(',').map(&:strip).reject(&:empty?)
  if tags_to_exclude.empty?
    puts 'Error: Please set TAGS_TO_EXCLUDE to the business unit tags to exclude.'
    exit 1
  end
  bu_mapping = OpsgenieTools::Tagging.normalise_bu_mapping(JSON.parse(ENV['CLIENT_TO_BU_MAPPING'] || '{}'))
  client_tag_mapping = JSON.parse(ENV['CLIENT_TAG_MAPPING'] || '{}')

  client = OpsgenieTools::Client.new(api_key)

  alerts = client.alerts(OpsgenieTools::Query.without_tags(tags_to_exclude, since: Date.today - 30))

  untagged_alerts = []
  suggestions = {}

  if alerts.empty?
    puts 'No alerts found without the specified tags.'
  else
    alerts.each do |alert|
      puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"

      # Prefer the alert's own client_* tag, then fall back to matching the
      # message against CLIENT_TAG_MAPPING as client_tags.rb does
      client_tag = OpsgenieTools::Tagging.client_tag_on_alert(alert)
      matched_bu = client_tag && bu_mapping[client_tag]

      if matched_bu
        puts "Matched client tag '#{client_tag}'."
      else
        message_tag = OpsgenieTools::Tagging.client_tag_from_message(alert['message'], client_tag_mapping)
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
        begin
          client.add_tag(alert['id'], matched_bu)
          puts "Automatically added tag '#{matched_bu}' to alert '#{alert['id']}' based on client tag '#{client_tag}'."
        rescue OpsgenieTools::Error => e
          puts "Error: Unable to add tag '#{matched_bu}' to alert '#{alert['id']}': #{e.message}"
        end
        next
      end

      # If no match, prompt the user
      new_tag = prompt_for_tag(tags_to_exclude + ['skip'])
      if new_tag == 'skip'
        untagged_alerts << alert
        next
      end

      begin
        client.add_tag(alert['id'], new_tag)
      rescue OpsgenieTools::Error => e
        puts "Error: Unable to add tag '#{new_tag}' to alert '#{alert['id']}': #{e.message}"
        next
      end

      puts "Added tag '#{new_tag}' to alert '#{alert['id']}'."
      if client_tag
        suggestions[client_tag] ||= {}
        suggestions[client_tag][new_tag] = suggestions[client_tag].fetch(new_tag, 0) + 1
      end
    end
  end

  report_suggestions(suggestions, bu_mapping)
  report_untagged(untagged_alerts, client)
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
