module RubyWeather
  class Error < StandardError; end
  class UsageError < Error; end
  class HelpRequested < Error; end
  class LocationError < Error; end
  class ProviderError < Error; end
end
