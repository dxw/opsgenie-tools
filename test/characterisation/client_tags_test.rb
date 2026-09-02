require "test_helper"
require "stringio"
require "date"
require "opsgenie_tools"

class ClientTagsCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["CLIENT_TAG_MAPPING"] = '{"alpha":"client_alpha"}'
  end

  def teardown
    ENV.replace(@env)
  end

  # ARGV[0] is unset in the test process, so the script's default of 30
  # applies. This is exactly what M1 (with_client_tag instead of
  # without_client_tag) would get wrong: it would fetch already-tagged
  # alerts and re-tag them.
  def expected_query
    OpsgenieTools::Query.without_client_tag(since: Date.today - 30)
  end

  def test_the_client_tag_prompt_skips_at_eof
    load_script("client_tags.rb")

    out, _err = capture_io do
      assert_equal "skip", prompt_for_client_tag(input: StringIO.new(""))
    end

    assert_match(/Enter client name/, out)
  end

  def test_skipping_every_prompt_is_unchanged
    stub_alerts_pages(fixture("alerts_tagging"), [], query: expected_query)
    stub_request(:post, %r{https://api\.opsgenie\.com/v2/alerts/.+/tags})
      .to_return(status: 202, body: "{}")
    load_script("client_tags.rb")

    out, err = capture_io do
      $stdin = StringIO.new("\n" * 10)
      begin
        main
      ensure
        $stdin = STDIN
      end
    end

    assert_matches_baseline("client-tags-all-skipped", out)
    assert_equal "", err
  end

  def test_an_api_error_fetching_alerts_aborts_the_run
    stub_alerts_page(alerts: [], status: 500, body: "boom", query: expected_query)
    load_script("client_tags.rb")

    error = assert_raises(SystemExit) { capture_io { main } }
    assert_equal 1, error.status
  end

  def test_a_failed_tag_write_reports_and_continues_to_the_next_alert
    stub_alerts_pages(fixture("alerts_tagging"), [], query: expected_query)
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/aaaaaaaa-0000-0000-0000-000000000101/tags")
      .to_return(status: 422, body: "boom")
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/aaaaaaaa-0000-0000-0000-000000000102/tags")
      .to_return(status: 202, body: "{}")
    ENV["CLIENT_TAG_MAPPING"] = '{"alpha":"client_alpha","status.example.com":"client_beta"}'
    load_script("client_tags.rb")

    out, = capture_io do
      $stdin = StringIO.new("\n" * 10)
      begin
        main
      ensure
        $stdin = STDIN
      end
    end

    assert_includes out, "Error: Unable to add tag 'client_alpha' to alert 'aaaaaaaa-0000-0000-0000-000000000101':"
    assert_includes out,
                     "Automatically added tag 'client_beta' to alert 'aaaaaaaa-0000-0000-0000-000000000102' " \
                     "based on client name."
  end
end
