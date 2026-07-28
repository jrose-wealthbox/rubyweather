require "json"

module RubyWeather
  class LocationResolver
    ENDPOINT = "https://geocoding-api.open-meteo.com/v1/search".freeze

    def initialize(transport:)
      @transport = transport
    end

    def call(query)
      result = results_for(query).first
      raise LocationError, "No location found for #{query.inspect}" unless result

      Location.from_api(query:, attributes: result)
    rescue LocationError, ProviderError
      raise
    rescue JSON::ParserError, KeyError, TypeError => error
      raise ProviderError, "Invalid geocoding response: #{error.message}"
    end

    private

    def results_for(query)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(name: query, count: 10, language: "en", format: "json")
      results = JSON.parse(@transport.get(uri)).fetch("results", [])
      raise TypeError, "results must be an array" unless results.is_a?(Array)

      results
    end
  end
end
