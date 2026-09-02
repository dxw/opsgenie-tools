require "rake/testtask"

Rake::TestTask.new(:unit) do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/unit/**/*_test.rb"]
  t.warning = false
end

# Characterisation tests load whole scripts. Two pairs of scripts define
# colliding top-level constants (BASE_URL and LIMIT in the statistics scripts,
# API_KEY elsewhere), so each file gets its own Ruby process.
desc "Run characterisation tests, one process per file"
task :characterisation do
  files = FileList["test/characterisation/**/*_test.rb"]
  failed = files.reject do |file|
    sh("bundle", "exec", "ruby", "-Ilib", "-Itest", file) { |ok, _status| ok }
  end
  raise "characterisation failures: #{failed.join(", ")}" unless failed.empty?
end

task test: %i[unit characterisation]
task default: :test
