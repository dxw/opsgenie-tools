require "test_helper"
require "opsgenie_tools"

class TaggingTest < Minitest::Test
  T = OpsgenieTools::Tagging

  def test_normalise_adds_the_missing_prefix_and_downcases
    assert_equal({ "client_alpha" => "bu1", "client_beta" => "bu2" },
                 T.normalise_bu_mapping("Alpha" => "bu1", "client_BETA" => "bu2"))
  end

  def test_client_tag_on_alert_finds_the_tag
    assert_equal "client_alpha", T.client_tag_on_alert("tags" => %w[OOH client_alpha])
  end

  def test_client_tag_on_alert_ignores_the_bare_prefix
    assert_nil T.client_tag_on_alert("tags" => %w[OOH client_])
  end

  def test_client_tag_on_alert_downcases
    assert_equal "client_alpha", T.client_tag_on_alert("tags" => %w[Client_Alpha])
  end

  def test_client_tag_on_alert_with_no_tags_key
    assert_nil T.client_tag_on_alert({})
  end

  def test_client_tag_on_alert_tolerates_a_null_tags_value
    assert_nil T.client_tag_on_alert("tags" => nil)
  end

  def test_needle_collisions_tolerates_a_null_tags_value
    reference = [{ "message" => "alpha is down", "tags" => nil }]

    assert_empty T.needle_collisions("alpha", "client_alpha", reference)
  end

  def test_client_tag_from_message_matches_case_insensitively
    assert_equal "client_alpha",
                 T.client_tag_from_message("ALARM: Alpha is down", "alpha" => "client_alpha")
  end

  def test_client_tag_from_message_with_no_match
    assert_nil T.client_tag_from_message("ALARM: something else", "alpha" => "client_alpha")
  end

  def test_client_tag_from_message_with_a_nil_message
    assert_nil T.client_tag_from_message(nil, "alpha" => "client_alpha")
  end

  def test_candidate_needles_from_a_url
    needles = T.candidate_needles("[Updown.io] Response timeout https://www.status.example.com/check")

    assert_includes needles, "status.example.com"
    assert_includes needles, "status.example"
    refute_includes needles, "www.status.example.com"
  end

  def test_candidate_needles_from_a_quoted_alarm_name
    needles = T.candidate_needles('ALARM: "ecs-asg-cpu-alpha-prod" in EU (London)')

    assert_includes needles, "ecs-asg-cpu-alpha-prod"
    assert_includes needles, "-alpha-"
    refute_includes needles, "-prod-"
    refute_includes needles, "-cpu-"
  end

  def test_candidate_needles_are_unique
    needles = T.candidate_needles("https://status.example.com and https://status.example.com")

    assert_equal needles.uniq, needles
  end

  def test_needle_collisions_counts_other_clients
    reference = [
      { "message" => "alpha is down", "tags" => %w[client_beta] },
      { "message" => "alpha is down again", "tags" => %w[client_beta] },
      { "message" => "alpha is fine", "tags" => %w[client_alpha] },
      { "message" => "unrelated", "tags" => %w[client_gamma] }
    ]

    assert_equal({ "client_beta" => 2 }, T.needle_collisions("alpha", "client_alpha", reference))
  end

  def test_needle_collisions_with_no_clashes
    assert_empty T.needle_collisions("alpha", "client_alpha", [])
  end
end
