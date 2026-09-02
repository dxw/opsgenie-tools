require "date"
require "time"

module OpsgenieTools
  # The payment month: we pay for the month the on-call week started in, so it
  # runs first Wednesday to first Wednesday rather than calendar month.
  module Payment
    HANDOVER_HOUR = 10

    class << self
      def window_for(date)
        [first_wednesday(date.year, date.month),
         first_wednesday(date.next_month.year, date.next_month.month)]
      end

      def hours_between(from, to)
        (to - from) / 3600
      end

      # period.user is nil for an unassigned slot. A period is clamped to the
      # window, then dropped if what remains falls outside it.
      def totals(periods, window:)
        window_start, window_end = window

        periods.each_with_object(Hash.new(0)) do |period, totals|
          next unless period.user

          from = [window_start, period.start_date.to_time].max
          to = [window_end, period.end_date.to_time].min
          next if to < window_start || from > window_end

          totals[period.user.full_name] += hours_between(from, to)
        end
      end

      def payment_for(hours, rate)
        format("%.2f", hours * rate)
      end

      private

      def first_wednesday(year, month)
        day = Date.new(year, month, 1)
        day += 1 until day.wday == 3
        day.to_time + HANDOVER_HOUR * 60 * 60
      end
    end
  end
end
