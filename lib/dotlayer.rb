module Dotlayer
  VERSION = "0.1.0"

  autoload :Detection, "dotlayer/detector"
  autoload :CLI, "dotlayer/cli"
  autoload :Config, "dotlayer/config"
  autoload :Detector, "dotlayer/detector"
  autoload :Resolver, "dotlayer/resolver"
  autoload :Stow, "dotlayer/stow"

  module Commands
    autoload :Adopt, "dotlayer/commands/adopt"
    autoload :Status, "dotlayer/commands/status"
    autoload :Install, "dotlayer/commands/install"
    autoload :Update, "dotlayer/commands/update"
    autoload :Doctor, "dotlayer/commands/doctor"
  end
end
