require "minitest/autorun"
require "webmock/minitest"
require "fileutils"
require "json"

WebMock.disable_net_connect!

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))

module TestHelpers
  ALERTS_URL = "https://api.opsgenie.com/v2/alerts".freeze
  LOADED_SCRIPTS = {}

  def fixture(name)
    JSON.parse(File.read(File.join(ROOT, "test", "fixtures", "#{name}.json")))
  end

  def baseline(name)
    File.join(ROOT, "test", "baselines", "#{name}.txt")
  end

  # Pass `query` to pin the query= param a script should be sending, built
  # with the same OpsgenieTools::Query call the script makes (or a Regexp
  # matching the query shape, for a script that issues one query per date
  # window). Leaving it nil leaves the query unconstrained.
  def stub_alerts_page(alerts:, offset: 0, status: 200, body: nil, query: nil)
    expected = { "limit" => "100", "offset" => offset.to_s }
    expected["query"] = query if query

    stub_request(:get, ALERTS_URL)
      .with(query: hash_including(expected))
      .to_return(
        status: status,
        body: body || JSON.dump("data" => alerts),
        headers: { "Content-Type" => "application/json" }
      )
  end

  # stub_alerts_pages(page_one, page_two) stubs offsets 0 and 100 in order.
  def stub_alerts_pages(*pages, query: nil)
    pages.each_with_index do |alerts, index|
      stub_alerts_page(alerts: alerts, offset: index * 100, query: query)
    end
  end

  # Scripts define top-level constants, so loading one more than once per
  # process re-runs those definitions and warns about already-initialized
  # constants. All mutable state lives in main's locals, so it is safe to
  # load each script at most once per process.
  def load_script(name)
    return if LOADED_SCRIPTS[name]

    load File.join(ROOT, name)
    LOADED_SCRIPTS[name] = true
  end
end

Minitest::Test.include(TestHelpers)

require "support/baseline"
