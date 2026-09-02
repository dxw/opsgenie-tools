require "test_helper"

class SchedulesCharacterisationTest < Minitest::Test
  def setup
    @env = ENV.to_h
    @argv = ARGV.dup
    ENV["OPSGENIE_API_KEY"] = "stub-key"
  end

  def teardown
    ENV.replace(@env)
    ARGV.replace(@argv)
  end

  def test_lists_all_schedules
    ARGV.replace([])
    stub_schedules([fixture("rota_schedules")])
    load_script("schedules.rb")

    out, err = capture_io { main }

    assert_matches_baseline("schedules", out)
    assert_equal "", err
  end

  def test_lists_rotations_for_named_schedule
    ARGV.replace(%w[-n OOH])
    stub_schedules([fixture("rota_schedules")])
    stub_request(:get, "https://api.opsgenie.com/v2/schedules/sched-1")
      .to_return(status: 200,
                 body: JSON.dump("data" => { "rotations" => [
                   { "id" => "rot-1", "name" => "Primary" },
                   { "id" => "rot-2", "name" => "Secondary" }
                 ] }),
                 headers: { "Content-Type" => "application/json" })
    load_script("schedules.rb")

    out, err = capture_io { main }

    assert_matches_baseline("schedules-rotations", out)
    assert_equal "", err
  end
end
