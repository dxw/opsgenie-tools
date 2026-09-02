require "test_helper"
require "opsgenie_tools"
require "date"
require "time"

class QueryTest < Minitest::Test
  Q = OpsgenieTools::Query

  def test_date_uses_the_opsgenie_day_format
    assert_equal "27-08-2026", Q.date(Date.new(2026, 8, 27))
  end

  def test_timestamp_uses_the_opsgenie_timestamp_format
    assert_equal "27-08-2026T02:05:00", Q.timestamp(Time.utc(2026, 8, 27, 2, 5, 0))
  end

  def test_created_after_without_tags
    assert_equal "createdAt>27-08-2026", Q.created_after(Date.new(2026, 8, 27))
  end

  def test_created_after_with_tags
    assert_equal "createdAt>27-08-2026 AND tags:(OOH AND sleepinghours)",
                 Q.created_after(Date.new(2026, 8, 27), tags: %w[OOH sleepinghours])
  end

  def test_created_between
    assert_equal "createdAt >= '01-08-2026T00:00:00' AND createdAt < '01-09-2026T00:00:00'",
                 Q.created_between(Time.utc(2026, 8, 1), Time.utc(2026, 9, 1))
  end

  def test_created_between_with_tags
    assert_includes Q.created_between(Time.utc(2026, 8, 1), Time.utc(2026, 9, 1), tags: %w[OOH]),
                    "AND tags:(OOH)"
  end

  def test_without_tags
    assert_equal "NOT (tags:bu1 OR tags:bu2) AND createdAt>03-08-2026",
                 Q.without_tags(%w[bu1 bu2], since: Date.new(2026, 8, 3))
  end

  def test_without_tags_ignores_blank_tag_names
    assert_equal "NOT (tags:bu1 OR tags:bu2) AND createdAt>03-08-2026",
                 Q.without_tags(["bu1", "", " bu2 "], since: Date.new(2026, 8, 3))
  end

  def test_without_tags_refuses_an_empty_exclusion_list
    # "NOT (tags:)" is not a query the API accepts, so it must never be built
    assert_raises(OpsgenieTools::Error) { Q.without_tags([], since: Date.new(2026, 8, 3)) }
    assert_raises(OpsgenieTools::Error) { Q.without_tags([" ", ""], since: Date.new(2026, 8, 3)) }
  end

  def test_tag_clauses_ignore_blank_tag_names
    assert_equal "createdAt>27-08-2026 AND tags:(OOH)",
                 Q.created_after(Date.new(2026, 8, 27), tags: ["OOH", ""])
  end

  def test_client_tag_queries
    assert_equal "tags:client_* AND createdAt>03-08-2026",
                 Q.with_client_tag(since: Date.new(2026, 8, 3))
    assert_equal "NOT tags:client_* AND createdAt>03-08-2026",
                 Q.without_client_tag(since: Date.new(2026, 8, 3))
  end
end
