require "json"
require "net/http"
require "openssl"
require "uri"

module OpsgenieTools
  class Client
    HOST = "https://api.opsgenie.com".freeze
    ALERTS_PATH = "/v2/alerts".freeze
    SCHEDULES_PATH = "/v2/schedules".freeze
    PAGE_LIMIT = 100
    # The API rejects offset + limit above this, which is why long ranges have
    # to be fetched a month at a time.
    MAX_OFFSET = 20_000
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    # Everything the transport can raise. Callers rescue OpsgenieTools::Error
    # and nothing else, so anything escaping this class unwrapped reaches the
    # operator as a stack trace instead of a message.
    TRANSPORT_ERRORS = [
      SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
    ].freeze

    def initialize(api_key)
      raise Error, "OPSGENIE_API_KEY is not set" if api_key.nil? || api_key.empty?

      @api_key = api_key
    end

    # Every alert matching the query, following pagination. Raises rather than
    # returning a partial list: a truncated result is indistinguishable from a
    # genuinely short one.
    def alerts(query)
      collected = []
      offset = 0

      loop do
        if offset + PAGE_LIMIT > MAX_OFFSET
          raise Error, "refusing to page past #{MAX_OFFSET} alerts; narrow the query"
        end

        page = fetch_page(query, offset)
        collected.concat(page)
        break if page.length < PAGE_LIMIT

        offset += PAGE_LIMIT
      end

      collected
    end

    # The schedules endpoint pages on paging.next rather than on page length,
    # so it cannot share the alerts loop.
    def schedules
      collected = []
      offset = 0

      loop do
        body = get_json("#{HOST}#{SCHEDULES_PATH}?limit=#{PAGE_LIMIT}&offset=#{offset}")
        collected.concat(body["data"] || [])
        break if body.dig("paging", "next").nil?

        offset += PAGE_LIMIT
      end

      collected
    end

    def schedule(id)
      get_json("#{HOST}#{SCHEDULES_PATH}/#{id}")["data"] || {}
    end

    def add_tag(alert_id, tag)
      uri = URI("#{HOST}#{ALERTS_PATH}/#{alert_id}/tags")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.dump("tags" => [tag])

      response = perform(request, uri)
      code = response.code.to_i
      unless [200, 202].include?(code)
        raise Error, "HTTP #{code} adding tag #{tag} to alert #{alert_id}: #{response.body}"
      end

      true
    end

    def alert_link(alert_id)
      "https://app.opsgenie.com/alert/detail/#{alert_id}"
    end

    private

    def get_json(url)
      uri = URI(url)
      response = perform(Net::HTTP::Get.new(uri), uri)
      code = response.code.to_i
      raise Error, "HTTP #{code} fetching #{uri.request_uri}: #{response.body}" unless code == 200

      parse(response.body)
    end

    def fetch_page(query, offset)
      uri = URI("#{HOST}#{ALERTS_PATH}?limit=#{PAGE_LIMIT}&offset=#{offset}" \
                "&query=#{URI.encode_www_form_component(query)}")
      response = perform(Net::HTTP::Get.new(uri), uri)
      code = response.code.to_i
      raise Error, "HTTP #{code} fetching alerts: #{response.body}" unless code == 200

      parse(response.body)["data"] || []
    end

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError => e
      # TypeError covers a 200 with no body at all, which JSON.parse(nil)
      # raises on
      raise Error, "unparseable response from Opsgenie: #{e.message}"
    end

    def perform(request, uri)
      request["Authorization"] = "GenieKey #{@api_key}"
      Net::HTTP.start(uri.hostname, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT,
                      read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    rescue *TRANSPORT_ERRORS => e
      raise Error, "#{e.class} talking to Opsgenie: #{e.message}"
    end
  end
end
