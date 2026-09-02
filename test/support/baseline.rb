module BaselineAssertions
  # Compares output against test/baselines/<name>.txt. Run with
  # UPDATE_BASELINES=1 to write a baseline from the current behaviour.
  def assert_matches_baseline(name, actual)
    path = baseline(name)

    if ENV["UPDATE_BASELINES"]
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, actual)
      skip "wrote baseline #{name}"
    end

    assert File.exist?(path), "no baseline #{name}; run with UPDATE_BASELINES=1"
    assert_equal File.read(path), actual, "#{name} output changed"
  end
end

Minitest::Test.include(BaselineAssertions)
