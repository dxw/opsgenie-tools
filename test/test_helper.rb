require "minitest/autorun"
require "webmock/minitest"
require "fileutils"
require "json"

WebMock.disable_net_connect!

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

module TestHelpers
  ALERTS_URL = "https://api.opsgenie.com/v2/alerts".freeze

  def fixture(name)
    JSON.parse(File.read(File.join(ROOT, "test", "fixtures", "#{name}.json")))
  end

  def baseline(name)
    File.join(ROOT, "test", "baselines", "#{name}.txt")
  end

  # The scripts build queries from Time.now, so match on the offset and leave
  # the date out of the expectation.
  def stub_alerts_page(alerts:, offset: 0, status: 200, body: nil)
    stub_request(:get, ALERTS_URL)
      .with(query: hash_including("limit" => "100", "offset" => offset.to_s))
      .to_return(
        status: status,
        body: body || JSON.dump("data" => alerts),
        headers: { "Content-Type" => "application/json" }
      )
  end

  # stub_alerts_pages(page_one, page_two) stubs offsets 0 and 100 in order.
  def stub_alerts_pages(*pages)
    pages.each_with_index do |alerts, index|
      stub_alerts_page(alerts: alerts, offset: index * 100)
    end
  end

  def load_script(name)
    load File.join(ROOT, name)
  end
end

Minitest::Test.include(TestHelpers)

require "support/baseline"
