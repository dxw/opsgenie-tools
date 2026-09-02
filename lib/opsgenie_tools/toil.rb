require "time"

module OpsgenieTools
  # TOIL owed for acknowledged out-of-hours alerts.
  #
  # Alerts closer together than WINDOW_SECONDS count once, per person and per
  # category, on the basis that one incident produces a burst of alerts. That
  # comparison is only meaningful in chronological order, and the Opsgenie
  # search returns alerts newest first, so this module sorts its own input
  # rather than trusting the caller to have done it.
  module Toil
    WINDOW_SECONDS = 1800
    # Order matters: an alert carrying both tags counts as sleeping.
    CATEGORIES = %w[sleepinghours wakinghours].freeze

    # An acknowledged alert can name no acknowledger. calculate must not credit
    # TOIL to nobody, so it drops those alerts. by_month is a per-month total
    # with no attribution, and has always counted them, so it groups them under
    # a sentinel that still gets its own de-dup window.
    UNATTRIBUTED = :unattributed

    Entry = Struct.new(:user, :category, :time, keyword_init: true)

    class << self
      def calculate(alerts, sleeping:, waking:, on_missing_acknowledger: nil)
        rates = rates_for(sleeping, waking)
        totals = {}

        each_counted(alerts, on_missing_acknowledger) do |entry|
          bucket = totals[entry.user] ||= {
            "sleepinghours" => 0, "wakinghours" => 0, "toil" => 0.0
          }
          bucket[entry.category] += 1
          bucket["toil"] += rates.fetch(entry.category)
        end

        totals
      end

      def by_month(alerts, sleeping:, waking:, on_missing_acknowledger: nil)
        rates = rates_for(sleeping, waking)
        months = {}

        each_counted(alerts, on_missing_acknowledger, unattributed: UNATTRIBUTED) do |entry|
          month = entry.time.strftime("%Y-%m")
          months[month] = (months[month] || 0.0) + rates.fetch(entry.category)
        end

        months
      end

      private

      def rates_for(sleeping, waking)
        { "sleepinghours" => sleeping, "wakinghours" => waking }
      end

      # Yields each alert that earns TOIL, oldest first, with bursts collapsed.
      def each_counted(alerts, on_missing_acknowledger, unattributed: nil)
        last_counted = {}

        countable(alerts, on_missing_acknowledger, unattributed: unattributed).each do |entry|
          key = [entry.user, entry.category]
          previous = last_counted[key]
          next if previous && (entry.time - previous) <= WINDOW_SECONDS

          last_counted[key] = entry.time
          yield entry
        end
      end

      def countable(alerts, on_missing_acknowledger, unattributed:)
        alerts.filter_map { |alert| entry_for(alert, on_missing_acknowledger, unattributed: unattributed) }
              .sort_by(&:time)
      end

      # unattributed is nil for calculate (drop such alerts) or
      # Toil::UNATTRIBUTED for by_month (count them under that shared key).
      def entry_for(alert, on_missing_acknowledger, unattributed:)
        return nil unless alert["acknowledged"]

        category = CATEGORIES.find { |c| Array(alert["tags"]).include?(c) }
        return nil unless category

        user = alert.dig("report", "acknowledgedBy")
        if user.nil?
          on_missing_acknowledger&.call(alert)
          return nil if unattributed.nil?

          user = unattributed
        end

        Entry.new(user: user, category: category, time: OpsgenieTools.created_at(alert))
      end

    end
  end
end
