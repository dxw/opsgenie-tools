require "test_helper"

class TagBusinessUnitCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    ENV["OPSGENIE_API_KEY"] = "stub-key"
    ENV["TAGS_TO_EXCLUDE"] = ""
    ENV["CLIENT_TO_BU_MAPPING"] = '{"client_alpha":"govpress"}'
    ENV["CLIENT_TAG_MAPPING"] = '{"alpha":"client_alpha"}'
  end

  def teardown
    ENV.replace(@env)
  end

  def test_skipping_the_prompt_is_unchanged
    stub_alerts_pages(fixture("alerts_tagging"), [])
    stub_request(:post, %r{https://api\.opsgenie\.com/v2/alerts/.+/tags})
      .to_return(status: 202, body: "{}")
    load_script("tag_business_unit.rb")

    out, err = capture_io do
      $stdin = StringIO.new("\n" * 10)
      begin
        main
      ensure
        $stdin = STDIN
      end
    end

    assert_matches_baseline("tag-business-unit", out)
    assert_equal "", err
  end
end
