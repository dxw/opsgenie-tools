require "test_helper"

# Loading a script must not run it, must not print, and must not make a
# request. WebMock.disable_net_connect! turns any request into a failure.
#
# Each script loads in its own forked child process. That keeps two things
# separate that a single shared process would conflate: ooh-stats.rb and
# stats.rb both define top-level BASE_URL and LIMIT, so loading both in one
# process makes Ruby warn about the redefinition regardless of what either
# script does on its own; and a script that prints or raises during load
# must not be able to hide behind a later script's clean run. fork inherits
# the parent's already-loaded WebMock, so disable_net_connect! still applies
# in the child and a script that reaches the network still fails there.
class LoadableTest < Minitest::Test
  SCRIPTS = %w[
    calculate-toil.rb
    ooh-stats.rb
    stats.rb
    tag_business_unit.rb
    client_tags.rb
  ].freeze

  def test_scripts_load_without_running
    SCRIPTS.each do |script|
      output, exitstatus = load_in_child(script)

      assert_equal "", output, "#{script} printed while loading:\n#{output}"

      case exitstatus
      when 0
        # loaded cleanly and defined its own main
      when 3
        flunk "#{script} defines no main method of its own"
      when 4
        flunk "#{script} raised while loading"
      else
        flunk "#{script} exited #{exitstatus} while loading"
      end
    end
  end

  private

  # Loads script in a forked child, capturing everything the child writes to
  # stdout/stderr. Exit 0 means script loaded cleanly and left behind a main
  # method sourced from script itself; 3 means main is missing or came from
  # some other script (defined earlier, in the parent, or by a prior
  # iteration); 4 means loading raised, including WebMock blocking a request.
  def load_in_child(script)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      $stdout.reopen(writer)
      $stderr.reopen(writer)
      $0 = "loadable-probe"
      status =
        begin
          load File.join(ROOT, script)
          source = defined?(main) ? method(:main).source_location&.first : nil
          source&.end_with?(script) ? 0 : 3
        rescue Exception => e
          warn "#{e.class}: #{e.message}"
          4
        end
      exit(status)
    end
    writer.close
    output = reader.read
    _, status = Process.waitpid2(pid)
    [output, status.exitstatus]
  end
end
