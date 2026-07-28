require "ruby_weather"
require_relative "support/fixture_helper"

RSpec.configure do |config|
  config.include FixtureHelper
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
