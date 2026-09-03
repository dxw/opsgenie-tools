require "date"

module OpsgenieTools
  # The rota week, which runs Wednesday to Wednesday, and the selection of a
  # person's next turn on it.
  module OnCall
    WEDNESDAY = 3

    class << self
      def next_wednesday(today: Date.today)
        today + ((WEDNESDAY - today.wday) % 7)
      end

      def slack_name(email, map)
        map[email] || "Unknown"
      end

      def next_period_for(periods, username:, after:)
        periods
          .select { |period| period.user&.username == username && period.start_date > after }
          .min_by(&:start_date)
      end
    end
  end
end
