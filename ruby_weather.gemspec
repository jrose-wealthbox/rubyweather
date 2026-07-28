Gem::Specification.new do |spec|
  spec.name = "ruby_weather"
  spec.version = "0.1.0"
  spec.summary = "Print an Open-Meteo forecast in the terminal"
  spec.authors = ["RubyWeather contributors"]
  spec.files = Dir["lib/**/*", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["rw"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "terminal-table", "~> 4.0"
end
