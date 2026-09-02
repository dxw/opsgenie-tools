module OpsgenieTools
  module Tagging
    CLIENT_TAG_PREFIX = "client_".freeze

    # segments that say nothing about which client an alert belongs to
    NOISE_SEGMENTS = %w[
      prod production staging test alarm cloudfront cloudwatch dalmatian dxw asg ecs
      alb elb rds sqs sns cpu mem ram disk blog blogs site sites www http https
      4xx 5xx 404 500 502 503 504 error timeout infrastructure cluster
    ].freeze

    class << self
      # keys may be given with or without the client_ prefix
      def normalise_bu_mapping(mapping)
        mapping.each_with_object({}) do |(client, bu), normalised|
          key = client.downcase
          key = "#{CLIENT_TAG_PREFIX}#{key}" unless key.start_with?(CLIENT_TAG_PREFIX)
          normalised[key] = bu
        end
      end

      def client_tag_on_alert(alert)
        Array(alert["tags"]).map(&:downcase).find do |tag|
          # ignore the bare 'client_' tag some alerts carry
          tag.start_with?(CLIENT_TAG_PREFIX) && tag.length > CLIENT_TAG_PREFIX.length
        end
      end

      def client_tag_from_message(message, client_tag_mapping)
        return nil if message.nil?

        _, tag = client_tag_mapping.find { |needle, _| message.downcase.include?(needle.downcase) }
        tag&.downcase
      end

      # strings from the message that could be used as a CLIENT_TAG_MAPPING key,
      # following the styles already in use: 'england.nhs' from a URL, '-gds-prod'
      # from a CloudWatch alarm name
      def candidate_needles(message)
        candidates = []

        message.to_s.scan(%r{https?://([^/\s"']+)}i) do |host,|
          host = host.downcase.sub(/\Awww\./, "")
          candidates << host
          labels = host.split(".")
          candidates << labels[0..-2].join(".") if labels.length > 2
        end

        message.to_s.scan(/"([^"]{1,40})"/) do |quoted,|
          quoted = quoted.downcase
          next if quoted.include?(" ")

          candidates << quoted
          quoted.split("-").each do |segment|
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
          .select { |alert| alert["message"].to_s.downcase.include?(needle.downcase) }
          .flat_map { |alert| Array(alert["tags"]).grep(/^client_./i).map(&:downcase) }
          .reject { |other| other == tag.downcase }
          .tally
      end
    end
  end
end
