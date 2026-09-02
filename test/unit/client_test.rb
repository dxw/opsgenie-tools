require "test_helper"
require "opsgenie_tools"

class ClientTest < Minitest::Test
  def setup
    @client = OpsgenieTools::Client.new("stub-key")
  end

  def full_page
    Array.new(100) { |i| { "tinyId" => i.to_s } }
  end

  def test_requires_an_api_key
    error = assert_raises(OpsgenieTools::Error) { OpsgenieTools::Client.new(nil) }
    assert_match(/OPSGENIE_API_KEY/, error.message)
    assert_raises(OpsgenieTools::Error) { OpsgenieTools::Client.new("") }
  end

  def test_sends_the_genie_key_header
    stub = stub_request(:get, TestHelpers::ALERTS_URL)
           .with(query: hash_including("limit" => "100"),
                 headers: { "Authorization" => "GenieKey stub-key" })
           .to_return(status: 200, body: JSON.dump("data" => []))

    @client.alerts("tags:OOH")

    assert_requested(stub)
  end

  def test_encodes_the_query
    stub_request(:get, TestHelpers::ALERTS_URL)
      .with(query: { "limit" => "100", "offset" => "0",
                     "query" => "tags:OOH AND createdAt>01-08-2026" })
      .to_return(status: 200, body: JSON.dump("data" => []))

    @client.alerts("tags:OOH AND createdAt>01-08-2026")
  end

  def test_follows_pagination_until_a_short_page
    stub_alerts_pages(full_page, full_page, [{ "tinyId" => "200" }])

    assert_equal 201, @client.alerts("tags:OOH").length
  end

  def test_stops_after_a_single_short_page
    stub_alerts_pages([{ "tinyId" => "1" }])

    assert_equal 1, @client.alerts("tags:OOH").length
    assert_not_requested(:get, TestHelpers::ALERTS_URL,
                         query: hash_including("offset" => "100"))
  end

  def test_raises_on_a_non_200
    stub_alerts_page(alerts: [], status: 503, body: "upstream boom")

    error = assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
    assert_match(/HTTP 503/, error.message)
    assert_match(/upstream boom/, error.message)
  end

  def test_raises_on_a_non_200_partway_through
    stub_alerts_page(alerts: full_page, offset: 0)
    stub_alerts_page(alerts: [], offset: 100, status: 500, body: "boom")

    assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
  end

  def test_treats_a_missing_data_key_as_no_alerts
    stub_alerts_page(alerts: [], body: JSON.dump("took" => 0.1))

    assert_equal [], @client.alerts("tags:OOH")
  end

  def test_raises_on_unparseable_json
    stub_alerts_page(alerts: [], body: "<html>gateway timeout</html>")

    error = assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
    assert_match(/unparseable/, error.message)
  end

  def test_refuses_to_page_past_the_offset_ceiling
    stub_request(:get, TestHelpers::ALERTS_URL)
      .with(query: hash_including("limit" => "100"))
      .to_return(status: 200, body: JSON.dump("data" => full_page))

    error = assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
    assert_match(/20000/, error.message)
  end

  def test_add_tag_posts_the_tag
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/abc-123/tags")
      .with(body: JSON.dump("tags" => ["client_alpha"]),
            headers: { "Content-Type" => "application/json" })
      .to_return(status: 202, body: "{}")

    assert @client.add_tag("abc-123", "client_alpha")
  end

  def test_add_tag_raises_on_failure
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/abc-123/tags")
      .to_return(status: 422, body: "bad tag")

    error = assert_raises(OpsgenieTools::Error) { @client.add_tag("abc-123", "client_alpha") }
    assert_match(/HTTP 422/, error.message)
  end

  def test_translates_a_transport_error
    stub_request(:get, TestHelpers::ALERTS_URL)
      .with(query: hash_including("limit" => "100"))
      .to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))

    error = assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
    assert_match(/SocketError talking to Opsgenie/, error.message)
  end

  def test_translates_a_timeout
    stub_request(:get, TestHelpers::ALERTS_URL)
      .with(query: hash_including("limit" => "100"))
      .to_timeout

    error = assert_raises(OpsgenieTools::Error) { @client.alerts("tags:OOH") }
    assert_match(/talking to Opsgenie/, error.message)
  end

  def test_translates_a_transport_error_on_a_tag_write
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/abc-123/tags").to_timeout

    assert_raises(OpsgenieTools::Error) { @client.add_tag("abc-123", "client_alpha") }
  end

  def test_sets_connection_timeouts
    assert_equal 10, OpsgenieTools::Client::OPEN_TIMEOUT
    assert_equal 30, OpsgenieTools::Client::READ_TIMEOUT
  end

  # A 200 always carries a String body, so JSON.parse(nil) cannot be reached
  # through #alerts. This pins the defensive branch itself.
  def test_parse_translates_a_nil_body
    error = assert_raises(OpsgenieTools::Error) { @client.send(:parse, nil) }
    assert_match(/unparseable response from Opsgenie/, error.message)
  end

  def test_alert_link
    assert_equal "https://app.opsgenie.com/alert/detail/abc-123",
                 @client.alert_link("abc-123")
  end
end
