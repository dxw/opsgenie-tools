require "opsgenie"

module OpsgenieTools
  # Intended to be the only place in this repository that names
  # Opsgenie:: constants.
  #
  # The gem returns nil for a schedule it cannot find and digs blindly into a
  # timeline response, so an expired key or a deleted schedule arrives at the
  # caller as NoMethodError on nil. This wraps those failures as
  # OpsgenieTools::Error, which is what the scripts rescue.
  class Rota
    def initialize(api_key)
      raise Error, "OPSGENIE_API_KEY is not set" if api_key.nil? || api_key.empty?

      Opsgenie.configure(api_key: api_key)
    end

    def schedule(id)
      found = Opsgenie::Schedule.find_by_id(id)
      raise Error, "no schedule #{id}" if found.nil?

      found
    rescue Opsgenie::ConfigurationError => e
      raise Error, e.message
    rescue NoMethodError
      raise Error, "no usable schedule #{id}"
    end

    def timeline(id, from:, months:)
      raise ArgumentError, "from must be a date, got #{from.inspect}" unless from.respond_to?(:to_datetime)

      schedule(id).timeline(date: from, interval: months, interval_unit: :months)
    rescue NoMethodError
      raise Error, "no usable timeline for schedule #{id}"
    end

    # The gem maps each participant through User.find_by_username, which
    # returns nil for a name its unpaged users?limit=500 fetch missed —
    # any organisation above 500 users, or a deactivated participant. Drop
    # those here so callers only ever see resolved users.
    def on_call(id, at:)
      raise ArgumentError, "at must not be nil" if at.nil?

      schedule(id).on_calls(at).compact
    rescue NoMethodError
      raise Error, "no usable on-call list for schedule #{id}"
    end
  end
end
