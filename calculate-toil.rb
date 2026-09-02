#!/usr/bin/env ruby
# Report the TOIL owed to each person for the out-of-hours alerts they
# acknowledged, so their line manager knows what should have been claimed.
require "date"
require "time"
require "dotenv"
require_relative "lib/opsgenie_tools"

Dotenv.load

def main
  api_key = ENV["OPSGENIE_API_KEY"]
  num_days = ENV["NUM_DAYS"] ? ENV["NUM_DAYS"].to_i : 7
  tags = ENV["TAGS"] ? ENV["TAGS"].split(",") : []
  sleeping = ENV["TOIL_SLEEPING_HOURS"] ? ENV["TOIL_SLEEPING_HOURS"].to_f : 0.0
  waking = ENV["TOIL_WAKING_HOURS"] ? ENV["TOIL_WAKING_HOURS"].to_f : 0.0

  query = OpsgenieTools::Query.created_after(Date.today - num_days, tags: tags)
  alerts = OpsgenieTools::Client.new(api_key).alerts(query)

  totals = OpsgenieTools::Toil.calculate(alerts, sleeping: sleeping, waking: waking)

  alerts.sort_by { |alert| OpsgenieTools.created_at(alert) }.each do |alert|
    next unless alert["acknowledged"]

    acknowledged_by = alert.dig("report", "acknowledgedBy")
    if acknowledged_by.nil?
      warn "Alert #{alert["tinyId"]} is acknowledged but names no acknowledger; skipping it."
      next
    end

    puts "Message: #{alert["message"]}\nAlert #{alert["tinyId"]} was acknowledged by #{acknowledged_by}. Created at: #{OpsgenieTools.created_at(alert)}."
  end

  puts "\nSummary of the number of alerts acknowledged by each user:"
  totals.each do |user, counts|
    puts "#{user} acknowledged #{counts["sleepinghours"]} alerts during sleepinghours and #{counts["wakinghours"]} alerts during wakinghours. This corresponds to #{counts["toil"]} TOIL."
  end
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

main if __FILE__ == $0
