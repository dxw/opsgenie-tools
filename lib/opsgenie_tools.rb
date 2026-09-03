require "time"

module OpsgenieTools
  Error = Class.new(StandardError)

  # An alert whose createdAt is missing, null or unparseable is an Opsgenie
  # contract failure rather than a bug here, so it surfaces as
  # OpsgenieTools::Error like every other operational failure. The scripts
  # rescue that and nothing else, so a KeyError, TypeError or ArgumentError
  # escaping would reach the operator as a stack trace.
  def self.created_at(alert)
    Time.parse(alert.fetch("createdAt"))
  rescue KeyError
    raise Error, "alert #{identify(alert)} has no createdAt"
  rescue TypeError, ArgumentError => e
    raise Error, "alert #{identify(alert)} has an unusable createdAt: #{e.message}"
  end

  def self.identify(alert)
    alert["tinyId"] || alert["id"] || "(unidentified)"
  end
end

require_relative "opsgenie_tools/query"
require_relative "opsgenie_tools/client"
require_relative "opsgenie_tools/toil"
require_relative "opsgenie_tools/tagging"
require_relative "opsgenie_tools/stats"
require_relative "opsgenie_tools/rota"
require_relative "opsgenie_tools/payment"
require_relative "opsgenie_tools/on_call"
