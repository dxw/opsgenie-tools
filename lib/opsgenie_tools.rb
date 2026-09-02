module OpsgenieTools
  Error = Class.new(StandardError)
end

require_relative "opsgenie_tools/query"
require_relative "opsgenie_tools/client"
require_relative "opsgenie_tools/toil"
require_relative "opsgenie_tools/tagging"
require_relative "opsgenie_tools/stats"
