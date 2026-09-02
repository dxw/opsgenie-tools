require "test_helper"
require "stringio"
require "date"
require "opsgenie_tools"

class TagBusinessUnitCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["TAGS_TO_EXCLUDE"] = "govpress,deliveryplus"
    ENV["CLIENT_TO_BU_MAPPING"] = '{"client_alpha":"govpress"}'
    ENV["CLIENT_TAG_MAPPING"] = '{"alpha":"client_alpha"}'
  end

  def teardown
    ENV.replace(@env)
  end

  def expected_query
    OpsgenieTools::Query.without_tags(%w[govpress deliveryplus], since: Date.today - 30)
  end

  def test_the_tag_prompt_skips_at_eof_rather_than_taking_the_default
    load_script("tag_business_unit.rb")

    capture_io do
      # pressing enter selects the default tag, but at EOF nobody chose it
      assert_equal "skip", prompt_for_tag(%w[bu1 bu2 skip], input: StringIO.new(""))
      assert_equal "bu1", prompt_for_tag(%w[bu1 bu2 skip], input: StringIO.new("\n"))
    end
  end

  def test_an_unknown_option_re_prompts_rather_than_applying_the_default
    load_script("tag_business_unit.rb")

    out, = capture_io do
      assert_equal "skip", prompt_for_tag(%w[govpress deliveryplus skip],
                                          input: StringIO.new("99\n3\n"))
    end

    assert_match(/There is no option 99\./, out)
  end

  def test_an_empty_exclusion_list_refuses_to_run
    ENV["TAGS_TO_EXCLUDE"] = ""
    load_script("tag_business_unit.rb")

    out, = capture_io do
      error = assert_raises(SystemExit) { main }
      assert_equal 1, error.status
    end

    assert_match(/Please set TAGS_TO_EXCLUDE/, out)
  end

  def test_skipping_the_prompt_is_unchanged
    stub_alerts_pages(fixture("alerts_tagging"), [], query: expected_query)
    stub_request(:post, %r{https://api\.opsgenie\.com/v2/alerts/.+/tags})
      .to_return(status: 202, body: "{}")
    load_script("tag_business_unit.rb")

    out, err = capture_io do
      $stdin = StringIO.new("3\n" * 10)
      begin
        main
      ensure
        $stdin = STDIN
      end
    end

    assert_matches_baseline("tag-business-unit", out)
    assert_equal "", err
  end

  def test_an_api_error_fetching_alerts_aborts_the_run
    stub_alerts_page(alerts: [], status: 500, body: "boom", query: expected_query)
    load_script("tag_business_unit.rb")

    error = assert_raises(SystemExit) { capture_io { main } }
    assert_equal 1, error.status
  end

  def test_a_failed_tag_write_reports_and_continues_to_the_next_alert
    alerts = [
      { "id" => "id-1", "message" => "alpha is down", "tags" => %w[client_alpha] },
      { "id" => "id-2", "message" => "alpha is down again", "tags" => %w[client_alpha] }
    ]
    stub_alerts_pages(alerts, [], query: expected_query)
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/id-1/tags")
      .to_return(status: 422, body: "boom")
    stub_request(:post, "https://api.opsgenie.com/v2/alerts/id-2/tags")
      .to_return(status: 202, body: "{}")
    load_script("tag_business_unit.rb")

    out, = capture_io do
      $stdin = StringIO.new("\n" * 10)
      begin
        main
      ensure
        $stdin = STDIN
      end
    end

    assert_includes out, "Error: Unable to add tag 'govpress' to alert 'id-1':"
    assert_includes out, "Automatically added tag 'govpress' to alert 'id-2' based on client tag 'client_alpha'."
  end
end
