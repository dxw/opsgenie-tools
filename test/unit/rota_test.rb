require "test_helper"
require "opsgenie_tools"
require "date"

class RotaTest < Minitest::Test
  def setup
    reset_gem_user_cache
    @rota = OpsgenieTools::Rota.new("stub-key")
  end

  def test_requires_an_api_key
    assert_raises(OpsgenieTools::Error) { OpsgenieTools::Rota.new(nil) }
    assert_raises(OpsgenieTools::Error) { OpsgenieTools::Rota.new("") }
  end

  def test_finds_a_schedule
    stub_schedule("sched-1")

    assert_equal "sched-1", @rota.schedule("sched-1").id
  end

  def test_a_missing_schedule_raises
    stub_missing_schedule("sched-1")

    error = assert_raises(OpsgenieTools::Error) { @rota.schedule("sched-1") }
    assert_match(/sched-1/, error.message)
  end

  def test_a_schedule_with_no_rotations_raises
    stub_request(:get, "https://api.opsgenie.com/v2/schedules/sched-1")
      .with(query: { "identifierType" => "id" })
      .to_return(status: 200,
                 body: JSON.dump("data" => { "id" => "sched-1", "name" => "OOH" }),
                 headers: { "Content-Type" => "application/json" })

    error = assert_raises(OpsgenieTools::Error) { @rota.schedule("sched-1") }
    assert_match(/sched-1/, error.message)
  end

  def test_returns_timeline_rotations
    stub_schedule("sched-1")
    stub_timeline("sched-1", query: { "date" => "2026-09-02T00:00:00+00:00",
                                       "interval" => "2", "intervalUnit" => "months" })
    stub_users

    rotations = @rota.timeline("sched-1", from: Date.new(2026, 9, 2), months: 2)

    assert_equal %w[rot-1 rot-2], rotations.map(&:id)
    assert_equal "First Example", rotations.first.periods.first.user.full_name
  end

  def test_a_timeline_with_no_final_timeline_raises
    stub_schedule("sched-1")
    stub_timeline("sched-1", body: { "message" => "unauthorised" },
                              query: { "date" => "2026-09-02T00:00:00+00:00",
                                       "interval" => "2", "intervalUnit" => "months" })

    error = assert_raises(OpsgenieTools::Error) do
      @rota.timeline("sched-1", from: Date.new(2026, 9, 2), months: 2)
    end
    assert_match(/timeline/, error.message)
  end

  def test_a_nil_from_raises_argument_error
    assert_raises(ArgumentError) do
      @rota.timeline("sched-1", from: nil, months: 2)
    end
  end

  def test_returns_on_call_users
    stub_schedule("sched-1")
    stub_on_calls("sched-1", query: { "date" => "2026-09-02T19:00:00+00:00" })
    stub_users

    users = @rota.on_call("sched-1", at: DateTime.new(2026, 9, 2, 19, 0, 0))

    assert_equal ["first@example.invalid"], users.map(&:username)
  end

  # The gem's User.find_by_username returns nil for a participant its
  # unpaged users?limit=500 fetch missed. Rota#on_call must drop that
  # nil rather than hand a caller a list it will crash iterating.
  def test_an_unresolved_participant_is_dropped
    stub_schedule("sched-1")
    stub_on_calls("sched-1", query: { "date" => "2026-09-02T19:00:00+00:00" },
                              body: { "data" => { "onCallParticipants" => [
                                { "type" => "user", "name" => "first@example.invalid" },
                                { "type" => "user", "name" => "missing@example.invalid" }
                              ] } })
    stub_users

    users = @rota.on_call("sched-1", at: DateTime.new(2026, 9, 2, 19, 0, 0))

    assert_equal ["first@example.invalid"], users.map(&:username)
  end

  def test_an_on_call_with_no_participants_raises
    stub_schedule("sched-1")
    stub_on_calls("sched-1", body: { "message" => "unauthorised" },
                              query: { "date" => "2026-09-02T19:00:00+00:00" })

    error = assert_raises(OpsgenieTools::Error) do
      @rota.on_call("sched-1", at: DateTime.new(2026, 9, 2, 19, 0, 0))
    end
    assert_match(/on-call/, error.message)
  end

  def test_a_nil_at_raises_argument_error
    assert_raises(ArgumentError) do
      @rota.on_call("sched-1", at: nil)
    end
  end
end
