require_relative "lib/dotlayer"

Gem::Specification.new do |spec|
  spec.name = "dotlayer"
  spec.version = Dotlayer::VERSION
  spec.authors = ["Douglas Andrade"]
  spec.email = ["douglas@51street.dev"]

  spec.summary = "Layered dotfiles management with GNU Stow"
  spec.description = "A convention-driven CLI wrapper around GNU Stow that adds layered package resolution, auto-detection, private repo overlays, and system file management."
  spec.homepage = "https://github.com/douglas/dotlayer"
  spec.license = "O-SaaSy"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*", "exe/*", "templates/*", "completions/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["dotlayer"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
end
