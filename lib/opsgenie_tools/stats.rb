require "date"
require "time"

module OpsgenieTools
  module Stats
    class << self
      # Build [start, next] Date pairs, one per calendar month spanned by the
      # range. The first pair starts at start_date; the last pair ends at
      # end_date.
      def month_windows(start_date, end_date)
        windows = []
        cursor = start_date
        while cursor < end_date
          first_of_next = if cursor.month == 12
                            Date.new(cursor.year + 1, 1, 1)
                          else
                            Date.new(cursor.year, cursor.month + 1, 1)
                          end
          window_end = [first_of_next, end_date].min
          windows << [cursor, window_end]
          cursor = first_of_next
        end
        windows
      end

      # Count alerts per calendar day, emitting a row for every day in the
      # range (inclusive of days with zero alerts).
      def daily_counts(alerts, start_date, end_date)
        counts = Hash.new(0)
        alerts.each do |alert|
          day = OpsgenieTools.created_at(alert).strftime("%Y-%m-%d")
          counts[day] += 1
        end

        rows = []
        day = start_date
        while day < end_date
          key = day.strftime("%Y-%m-%d")
          rows << [key, counts[key]]
          day += 1
        end
        rows
      end

      # Count alerts per calendar month, one row per month in the range.
      def monthly_totals(alerts, start_date, end_date)
        counts = Hash.new(0)
        alerts.each do |alert|
          month = OpsgenieTools.created_at(alert).strftime("%Y-%m")
          counts[month] += 1
        end

        month_windows(start_date, end_date).map do |window_start, _window_end|
          key = window_start.strftime("%Y-%m")
          [key, counts[key]]
        end
      end

      # Process alerts to create a summary report.
      #
      # For each alert that has a business unit tag (from business_units), we
      # count any matching time tags (from time_tags). Additionally, if the
      # alert has client tags (starting with "client_"), we count them for
      # that business unit.
      #
      # The summary includes overall company totals, per-business unit
      # totals, and client breakdowns per business unit.
      def summarise(alerts, business_units:, time_tags:)
        summary = { "company" => { totals: Hash.new(0) } }
        business_units.each do |bu|
          summary[bu] = { totals: Hash.new(0), clients: {} }
        end

        alerts.each do |alert|
          tags = alert["tags"] || []
          # Identify the business unit for this alert (first match).
          bu = business_units.find { |b| tags.include?(b) }
          next if bu.nil?

          present_time_tags = tags & time_tags
          next if present_time_tags.empty?

          # Update totals for both the business unit and company.
          present_time_tags.each do |ttag|
            summary[bu][:totals][ttag] += 1
            summary["company"][:totals][ttag] += 1
          end

          # Update client-specific counts.
          client_tags = tags.select { |t| t.start_with?("client_") }
          client_tags.each do |ctag|
            client_name = ctag.sub(/^client_/, "")
            summary[bu][:clients][client_name] ||= Hash.new(0)
            present_time_tags.each do |ttag|
              summary[bu][:clients][client_name][ttag] += 1
            end
          end
        end

        summary
      end
    end
  end
end
