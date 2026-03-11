module Dotlayer
  VERSION = "0.2.2"

  autoload :CLI, "dotlayer/cli"
  autoload :Config, "dotlayer/config"
  autoload :Detection, "dotlayer/detector"
  autoload :Detector, "dotlayer/detector"
  autoload :Output, "dotlayer/output"
  autoload :Repo, "dotlayer/config"
  autoload :Resolver, "dotlayer/resolver"
  autoload :Stow, "dotlayer/stow"

  module Commands
    autoload :Adopt, "dotlayer/commands/adopt"
    autoload :Doctor, "dotlayer/commands/doctor"
    autoload :Install, "dotlayer/commands/install"
    autoload :Status, "dotlayer/commands/status"
    autoload :Update, "dotlayer/commands/update"
  end
end
