# Stubs for the endpoints the opsgenie-schedule gem calls on the scripts'
# behalf. The gem builds its URLs with CGI.escape on a datetime, so these
# match on path and leave the query unconstrained unless a `query:` hash is
# given, the way stub_alerts_page does for the alerts endpoint. WebMock
# decodes the query when matching, so pin the "date" value as the plain
# datetime string (e.g. "2026-09-02T00:00:00+00:00"), not the escaped form.
module RotaStubs
  GEM_ROOT = "https://api.opsgenie.com/v2".freeze

  def stub_schedule(id, name: "OOH", rotations: [])
    stub_request(:get, "#{GEM_ROOT}/schedules/#{id}")
      .with(query: { "identifierType" => "id" })
      .to_return(status: 200,
                 body: JSON.dump("data" => { "id" => id, "name" => name,
                                             "rotations" => rotations }),
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_missing_schedule(id)
    stub_request(:get, "#{GEM_ROOT}/schedules/#{id}")
      .with(query: { "identifierType" => "id" })
      .to_return(status: 404, body: JSON.dump("message" => "not found"),
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_timeline(id, body: fixture("rota_timeline"), query: nil)
    stub = stub_request(:get, %r{#{Regexp.escape("#{GEM_ROOT}/schedules/#{id}/timeline")}})
    stub = stub.with(query: hash_including(query)) if query
    stub.to_return(status: 200, body: JSON.dump(body),
                   headers: { "Content-Type" => "application/json" })
  end

  def stub_users(body: fixture("rota_users"))
    stub_request(:get, "#{GEM_ROOT}/users").with(query: { "limit" => "500" })
      .to_return(status: 200, body: JSON.dump(body),
                 headers: { "Content-Type" => "application/json" })
  end

  def stub_on_calls(id, body: fixture("rota_on_calls"), query: nil)
    stub = stub_request(:get, %r{#{Regexp.escape("#{GEM_ROOT}/schedules/#{id}/on-calls")}})
    stub = stub.with(query: hash_including(query)) if query
    stub.to_return(status: 200, body: JSON.dump(body),
                   headers: { "Content-Type" => "application/json" })
  end

  # schedules.rb's own endpoint, which pages on paging.next
  def stub_schedules(pages)
    pages.each_with_index do |page, index|
      stub_request(:get, "#{GEM_ROOT}/schedules")
        .with(query: { "limit" => "100", "offset" => (index * 100).to_s })
        .to_return(status: 200, body: JSON.dump(page),
                   headers: { "Content-Type" => "application/json" })
    end
  end

  # Opsgenie::User.find memoises the whole user list in a class-level
  # instance variable, so it outlives a single test.
  def reset_gem_user_cache
    return unless defined?(Opsgenie::User)

    Opsgenie::User.instance_variable_set(:@users, nil)
  end
end

Minitest::Test.include(RotaStubs)
