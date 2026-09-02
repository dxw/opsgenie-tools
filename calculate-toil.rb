#!/usr/bin/env ruby
# script to calculate TOIL for each user based on the number of alerts acknowledged during sleeping hours and waking hours
require 'net/http'
require 'dotenv'
require 'time'
require 'json'
require 'uri'

# Load .env variables
Dotenv.load

def main
  # Opsgenie API Key
  api_key = ENV['OPSGENIE_API_KEY']

  # Get the number of days from environment variables or use default value of 7
  num_days = ENV['NUM_DAYS'] ? ENV['NUM_DAYS'].to_i : 7

  # Get the tags from environment variables or use empty string as default
  tags = ENV['TAGS'] ? ENV['TAGS'].split(",") : []

  # Get the TOIL for sleeping hours and waking hours
  toil_sleeping_hours = ENV['TOIL_SLEEPING_HOURS'] ? ENV['TOIL_SLEEPING_HOURS'].to_f : 0.0
  toil_waking_hours = ENV['TOIL_WAKING_HOURS'] ? ENV['TOIL_WAKING_HOURS'].to_f : 0.0

  # Get the date of num_days ago
  day_ago = (Time.now - num_days*24*60*60).strftime("%d-%m-%Y")

  limit = 100 # Maximum limit allowed by Opsgenie API

  # Fetch every alert matching the query, following the pagination until a page
  # comes back empty.
  def fetch_alerts(api_key, query, limit)
    alerts = []
    offset = 0

    loop do
      uri = URI("https://api.opsgenie.com/v2/alerts?limit=#{limit}&offset=#{offset}&query=#{URI.encode_www_form_component(query)}")

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "GenieKey #{api_key}"

      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = true
      response = http.request(request)

      unless response.code.to_i == 200
        warn "Error fetching alerts: HTTP #{response.code}: #{response.body}"
        exit 1
      end

      page = JSON.parse(response.body)['data'] || []
      break if page.empty?

      alerts.concat(page)
      offset += limit
    end

    alerts
  end

  # Create hash tables to track the count of alerts acknowledged by each user and the last acknowledgment time
  sleepinghours_ack_count = Hash.new(0)
  wakinghours_ack_count = Hash.new(0)
  last_acknowledged_time = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Time.at(0) } } # default to earliest possible time
  total_toil = Hash.new(0)

  # Add tags to the query if they are provided
  tag_query = tags.empty? ? "" : " AND tags:(" + tags.join(" AND ") + ")"
  query = "createdAt>#{day_ago}#{tag_query}"

  # The Opsgenie search returns the newest alert first, but the 30 minute de-dup
  # below only holds one timestamp per user and category, so it has to see the
  # alerts oldest first or every alert after the first looks like a duplicate.
  alerts = fetch_alerts(api_key, query, limit)
    .map { |alert| [Time.parse(alert['createdAt']), alert] }
    .sort_by { |alert_createdAt, _alert| alert_createdAt }

  alerts.each do |alert_createdAt, alert|
    alert_tinyId = alert['tinyId']
    alert_acknowledged = alert['acknowledged']
    next unless alert_acknowledged

    alert_acknowledged_by = alert.dig('report', 'acknowledgedBy')
    if alert_acknowledged_by.nil?
      warn "Alert #{alert_tinyId} is acknowledged but names no acknowledger; skipping it."
      next
    end

    alert_message = alert['message']

    # Check for special tags
    alert_tags = alert['tags'] || []

    if alert_tags.include?('sleepinghours')
      if (alert_createdAt - last_acknowledged_time[alert_acknowledged_by]['sleepinghours']) > 1800
        sleepinghours_ack_count[alert_acknowledged_by] += 1
        last_acknowledged_time[alert_acknowledged_by]['sleepinghours'] = alert_createdAt
        total_toil[alert_acknowledged_by] += toil_sleeping_hours
      end
    elsif alert_tags.include?('wakinghours')
      if (alert_createdAt - last_acknowledged_time[alert_acknowledged_by]['wakinghours']) > 1800
        wakinghours_ack_count[alert_acknowledged_by] += 1
        last_acknowledged_time[alert_acknowledged_by]['wakinghours'] = alert_createdAt
        total_toil[alert_acknowledged_by] += toil_waking_hours
      end
    end

    puts "Message: #{alert_message}\nAlert #{alert_tinyId} was acknowledged by #{alert_acknowledged_by}. Created at: #{alert_createdAt}."
  end

  # Output the summary and TOIL calculation
  puts "\nSummary of the number of alerts acknowledged by each user:"
  total_toil.each do |user, total|
    puts "#{user} acknowledged #{sleepinghours_ack_count[user]} alerts during sleepinghours and #{wakinghours_ack_count[user]} alerts during wakinghours. This corresponds to #{total} TOIL."
  end
end

main if __FILE__ == $0
