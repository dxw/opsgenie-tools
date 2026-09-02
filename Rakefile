require "rake/testtask"

Rake::TestTask.new(:unit) do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/unit/**/*_test.rb"]
  t.warning = false
end

# Characterisation tests load whole scripts. A characterisation test sharing
# a process with another script's characterisation test is not characterising
# that script alone, so each file gets its own Ruby process.
desc "Run characterisation tests, one process per file"
task characterisation: :guard_baselines do
  files = FileList["test/characterisation/**/*_test.rb"]
  failed = files.reject do |file|
    sh("bundle", "exec", "ruby", "-Ilib", "-Itest", file) { |ok, _status| ok }
  end
  raise "characterisation failures: #{failed.join(", ")}" unless failed.empty?
end

# UPDATE_BASELINES=1 makes assert_matches_baseline rewrite every baseline to
# match whatever the code currently prints and then skip, which Minitest does
# not treat as a failure. A stale shell export or a leaked CI variable would
# silently repin every baseline to a regression and report the suite green,
# so the full suite refuses to run in that mode. Regenerate one baseline at a
# time by running its characterisation file directly instead.
desc "Refuse to run the whole suite in baseline-writing mode"
task :guard_baselines do
  if ENV["UPDATE_BASELINES"]
    abort "UPDATE_BASELINES is set: refusing to run the full suite, which would " \
          "rewrite every baseline to match current behaviour and report success. " \
          "Regenerate one baseline by running its characterisation file directly."
  end
end

task test: %i[guard_baselines unit characterisation]
task default: :test
