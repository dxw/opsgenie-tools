module OpsgenieTools
  # The two date formats the Opsgenie search accepts, and the query strings
  # built from them. Four scripts rebuilt these by hand, with small
  # inconsistencies in spacing and quoting.
  module Query
    DAY_FORMAT = "%d-%m-%Y".freeze
    TIMESTAMP_FORMAT = "%d-%m-%YT%H:%M:%S".freeze

    class << self
      def date(value)
        value.strftime(DAY_FORMAT)
      end

      def timestamp(value)
        value.strftime(TIMESTAMP_FORMAT)
      end

      def created_after(since, tags: [])
        with_tags("createdAt>#{date(since)}", tags)
      end

      def created_between(from, to, tags: [])
        with_tags("createdAt >= '#{timestamp(from)}' AND createdAt < '#{timestamp(to)}'", tags)
      end

      def without_tags(tags, since:)
        names = tag_names(tags)
        # Splitting an empty or sloppy environment variable yields blanks, and
        # "NOT (tags:)" is not a query the API accepts. Refusing beats sending
        # it: the caller has no tags to exclude and needs to know.
        raise Error, "no tags to exclude" if names.empty?

        "NOT (tags:#{names.join(" OR tags:")}) AND createdAt>#{date(since)}"
      end

      def with_client_tag(since:)
        "tags:client_* AND createdAt>#{date(since)}"
      end

      def without_client_tag(since:)
        "NOT tags:client_* AND createdAt>#{date(since)}"
      end

      private

      def with_tags(clause, tags)
        names = tag_names(tags)
        return clause if names.empty?

        "#{clause} AND tags:(#{names.join(" AND ")})"
      end

      def tag_names(tags)
        Array(tags).map { |tag| tag.to_s.strip }.reject(&:empty?)
      end
    end
  end
end
