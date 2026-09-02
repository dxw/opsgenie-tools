#!/usr/bin/env ruby
# script to tag untagged alerts with a client tag
# requires the following environment variables:
#  OPSGENIE_API_KEY: API key for OpsGenie
#  CLIENT_TAG_MAPPING: JSON string mapping strings found in an alert message to
#  client tags (e.g. {"dalmatian": "client_dalmatian", "caselaw": "client_moj"})
#  Note: the script will prompt for the tag to add to the alerts if no client
#  match is found, then offer strings from the message to use as a mapping key
#  so the same client is matched automatically next time

require "json"
require "dotenv"
require "date"
require_relative "lib/opsgenie_tools"

Dotenv.load

def prompt_for_client_tag(input: $stdin)
  print 'Enter client name for the tag (client_$clientname), or leave blank to skip: '
  # nil means stdin is at EOF: nobody is there to answer, so skip rather than
  # crash on nil.chomp part way through a run
  client_name = input.gets.to_s.chomp
  return 'skip' if client_name.empty?

  "client_#{client_name}"
end

def prompt_for_needle(message, tag, reference_alerts, input: $stdin)
  candidates = OpsgenieTools::Tagging.candidate_needles(message).map do |needle|
    [needle, OpsgenieTools::Tagging.needle_collisions(needle, tag, reference_alerts)]
  end
  clean, colliding = candidates.partition { |_, collisions| collisions.empty? }
  candidates = clean + colliding

  puts "Which part of the message should match #{tag} in future?"
  candidates.each_with_index do |(needle, collisions), index|
    warning = collisions.empty? ? '' : "  (also matches #{collisions.map { |t, c| "#{t} x#{c}" }.join(', ')})"
    puts "#{index + 1}. #{needle}#{warning}"
  end
  puts "#{candidates.length + 1}. enter my own"
  puts "#{candidates.length + 2}. do not add a mapping"
  print 'Enter the number corresponding to the desired match: '

  choice = input.gets.to_s.chomp.to_i
  return candidates[choice - 1].first if choice.between?(1, candidates.length)
  return nil unless choice == candidates.length + 1

  print 'Enter the string that should match this client: '
  own = input.gets.to_s.chomp.downcase
  own.empty? ? nil : own
end

def report_suggestions(additions, client_tag_mapping)
  return if additions.empty?

  puts "\nSuggested CLIENT_TAG_MAPPING additions based on the tags you added by hand:"
  additions.each { |needle, tag| puts "  #{needle} => #{tag}" }
  puts "\nCopy this into your .env to avoid the same prompts next time:"
  puts "CLIENT_TAG_MAPPING=#{client_tag_mapping.to_json}"
end

def report_untagged(untagged_alerts, client)
  return if untagged_alerts.empty?

  puts "\nSkipped #{untagged_alerts.length} alert(s):"
  untagged_alerts.each { |alert| puts "  #{client.alert_link(alert['id'])} #{alert['message']}" }
end

# how far back to look for alerts to compare a candidate mapping needle against
REFERENCE_DAYS = 730

# A failed reference fetch must not cost the operator the suggestions and
# skip list from the rest of the run, so it is rescued here rather than
# left to unwind to main's rescue: this returns an empty list and the run
# continues with collision checking effectively disabled for its remainder.
def fetch_reference_alerts(client)
  puts "Fetching client tagged alerts from the last #{REFERENCE_DAYS} days to check suggestions against..."
  client.alerts(OpsgenieTools::Query.with_client_tag(since: Date.today - REFERENCE_DAYS))
rescue OpsgenieTools::Error => e
  puts "Error: Unable to fetch reference alerts to check suggestions against: #{e.message}"
  []
end

def main
  days = ARGV[0] ? ARGV[0].to_i : 30
  api_key = ENV['OPSGENIE_API_KEY']
  client_tag_mapping = JSON.parse(ENV['CLIENT_TAG_MAPPING'] || '{}')

  client = OpsgenieTools::Client.new(api_key)

  puts "Looking for alerts without a client tag from the last #{days} days..."
  alerts = client.alerts(OpsgenieTools::Query.without_client_tag(since: Date.today - days))

  untagged_alerts = []
  additions = {}
  reference_alerts = nil

  if alerts.empty?
    puts 'No alerts found without a client tag.'
  else
    alerts.each do |alert|
      puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"

      # Try to automatically tag based on client name in the message
      matched_tag = OpsgenieTools::Tagging.client_tag_from_message(alert["message"], client_tag_mapping)

      if matched_tag
        begin
          client.add_tag(alert['id'], matched_tag)
          puts "Automatically added tag '#{matched_tag}' to alert '#{alert['id']}' based on client name."
        rescue OpsgenieTools::Error => e
          puts "Error: Unable to add tag '#{matched_tag}' to alert '#{alert['id']}': #{e.message}"
        end
        next
      end

      # If no match, prompt the user
      new_tag = prompt_for_client_tag
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

      reference_alerts ||= fetch_reference_alerts(client)
      needle = prompt_for_needle(alert['message'], new_tag, reference_alerts)
      next if needle.nil?

      additions[needle] = new_tag
      # so the rest of this run tags matching alerts automatically
      client_tag_mapping[needle] = new_tag
    end
  end

  report_suggestions(additions, client_tag_mapping)
  report_untagged(untagged_alerts, client)
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
