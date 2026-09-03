#!/usr/bin/env ruby
# script to get the on call person for the next 4 weeks
require 'date'
require 'json'
require 'dotenv/load'
require_relative 'lib/opsgenie_tools'

# The hour at which "who is on call this week" is sampled.
SAMPLE_HOUR = 19

def main
  weeks = (ENV['OPSGENIE_WEEKS'] || 4).to_i
  rota = OpsgenieTools::Rota.new(ENV['OPSGENIE_API_KEY'])
  if ENV['EMAIL_TO_SLACK_MAP'].to_s.empty?
    raise OpsgenieTools::Error, 'Please set EMAIL_TO_SLACK_MAP to a JSON map of email to Slack name.'
  end

  email_to_slack_map =
    begin
      JSON.parse(ENV['EMAIL_TO_SLACK_MAP'])
    rescue JSON::ParserError => e
      raise OpsgenieTools::Error, "EMAIL_TO_SLACK_MAP is not valid JSON: #{e.message}"
    end

  puts "Week starting: 1st line / 2nd line"
  weeks.times do |i|
    wednesday = OpsgenieTools::OnCall.next_wednesday + i * 7
    date_time = DateTime.parse("#{wednesday.strftime('%Y-%m-%d')}T#{format('%02d:00:00', SAMPLE_HOUR)}")

    first_line = names_for(rota, ENV['OPSGENIE_SCHEDULE_ID'], date_time, email_to_slack_map)
    second_line = names_for(rota, ENV['OPSGENIE_SCHEDULE_ID_SECONDLINE'], date_time, email_to_slack_map)

    puts "#{wednesday.strftime('%Y-%m-%d')}: #{first_line} / #{second_line}"
  end
rescue OpsgenieTools::Error => e
  warn e.message
  exit 1
end

# A week with nobody on call used to leave a global at the previous week's
# value, so the same person was reported twice.
def names_for(rota, schedule_id, date_time, email_to_slack_map)
  users = rota.on_call(schedule_id, at: date_time)
  return 'Nobody' if users.empty?

  users.map { |user| "@#{OpsgenieTools::OnCall.slack_name(user.username, email_to_slack_map)}" }
       .join(', ')
end

main if __FILE__ == $0
