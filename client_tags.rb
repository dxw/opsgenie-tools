#!/usr/bin/env ruby
# script to tag untagged alerts with a client tag
# requires the following environment variables:
#  OPSGENIE_API_KEY: API key for OpsGenie
#  CLIENT_TAG_MAPPING: JSON string mapping strings found in an alert message to
#  client tags (e.g. {"dalmatian": "client_dalmatian", "caselaw": "client_moj"})
#  Note: the script will prompt for the tag to add to the alerts if no client
#  match is found, then offer strings from the message to use as a mapping key
#  so the same client is matched automatically next time

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
    fetch_alerts("NOT tags:client_* AND createdAt>#{date_threshold(days)}")
  end

  # already tagged alerts, used to check a candidate mapping needle does not
  # also match some other client's alerts
  def alerts_with_client_tags(days)
    fetch_alerts("tags:client_* AND createdAt>#{date_threshold(days)}")
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

  private

  def date_threshold(days)
    (Date.today - days).strftime('%d-%m-%Y')
  end

  def fetch_alerts(query)
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
end

def prompt_for_client_tag
  print 'Enter client name for the tag (client_$clientname), or leave blank to skip: '
  client_name = $stdin.gets.chomp
  return 'skip' if client_name.empty?

  "client_#{client_name}"
end

# segments that say nothing about which client an alert belongs to
NOISE_SEGMENTS = %w[
  prod production staging test alarm cloudfront cloudwatch dalmatian dxw asg ecs
  alb elb rds sqs sns cpu mem ram disk blog blogs site sites www http https
  4xx 5xx 404 500 502 503 504 error timeout infrastructure cluster
].freeze

# strings from the message that could be used as a CLIENT_TAG_MAPPING key,
# following the styles already in use: 'england.nhs' from a URL, '-gds-prod'
# from a CloudWatch alarm name
def candidate_needles(message)
  candidates = []

  message.to_s.scan(%r{https?://([^/\s"']+)}i) do |host,|
    host = host.downcase.sub(/\Awww\./, '')
    candidates << host
    labels = host.split('.')
    candidates << labels[0..-2].join('.') if labels.length > 2
  end

  message.to_s.scan(/"([^"]{1,40})"/) do |quoted,|
    quoted = quoted.downcase
    next if quoted.include?(' ')

    candidates << quoted
    quoted.split('-').each do |segment|
      next if segment.length < 3 || NOISE_SEGMENTS.include?(segment)

      candidates << "-#{segment}-"
    end
  end

  candidates.uniq
end

# client tags, other than the one being applied, on reference alerts the needle
# would also match: { 'client_foo' => 3 }
def needle_collisions(needle, tag, reference_alerts)
  reference_alerts
    .select { |alert| alert['message'].to_s.downcase.include?(needle.downcase) }
    .flat_map { |alert| alert.fetch('tags', []).grep(/^client_./i).map(&:downcase) }
    .reject { |other| other == tag.downcase }
    .tally
end

def prompt_for_needle(message, tag, reference_alerts)
  candidates = candidate_needles(message).map do |needle|
    [needle, needle_collisions(needle, tag, reference_alerts)]
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

  choice = $stdin.gets.to_s.chomp.to_i
  return candidates[choice - 1].first if choice.between?(1, candidates.length)
  return nil unless choice == candidates.length + 1

  print 'Enter the string that should match this client: '
  own = $stdin.gets.to_s.chomp.downcase
  own.empty? ? nil : own
end

def report_suggestions(additions, client_tag_mapping)
  return if additions.empty?

  puts "\nSuggested CLIENT_TAG_MAPPING additions based on the tags you added by hand:"
  additions.each { |needle, tag| puts "  #{needle} => #{tag}" }
  puts "\nCopy this into your .env to avoid the same prompts next time:"
  puts "CLIENT_TAG_MAPPING=#{client_tag_mapping.to_json}"
end

def report_untagged(untagged_alerts, opsgenie)
  return if untagged_alerts.empty?

  puts "\nSkipped #{untagged_alerts.length} alert(s):"
  untagged_alerts.each { |alert| puts "  #{opsgenie.alert_link(alert['id'])} #{alert['message']}" }
end

# how far back to look for alerts to compare a candidate mapping needle against
REFERENCE_DAYS = 730

days = ARGV[0] ? ARGV[0].to_i : 30
api_key = ENV['OPSGENIE_API_KEY']
client_tag_mapping = JSON.parse(ENV['CLIENT_TAG_MAPPING'] || '{}')

opsgenie = OpsGenie.new(api_key)

puts "Looking for alerts without a client tag from the last #{days} days..."
alerts = opsgenie.alerts_without_client_tags(days)

untagged_alerts = []
additions = {}
reference_alerts = nil

if alerts.empty?
  puts 'No alerts found without a client tag.'
else
  alerts.each do |alert|
    puts "Alert ID: #{alert['id']}, Message: #{alert['message']}"

    # Try to automatically tag based on client name in the message
    matched_tag = nil
    client_tag_mapping.each do |needle, tag|
      if alert['message'].to_s.downcase.include?(needle.downcase)
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
    unless %w[200 202].include?(response.code)
      puts "Error: Unable to add tag '#{new_tag}' to alert '#{alert['id']}' (status code: #{response.code})"
      next
    end

    puts "Added tag '#{new_tag}' to alert '#{alert['id']}'."

    reference_alerts ||= begin
      puts "Fetching client tagged alerts from the last #{REFERENCE_DAYS} days to check suggestions against..."
      opsgenie.alerts_with_client_tags(REFERENCE_DAYS)
    end
    needle = prompt_for_needle(alert['message'], new_tag, reference_alerts)
    next if needle.nil?

    additions[needle] = new_tag
    # so the rest of this run tags matching alerts automatically
    client_tag_mapping[needle] = new_tag
  end
end

report_suggestions(additions, client_tag_mapping)
report_untagged(untagged_alerts, opsgenie)
