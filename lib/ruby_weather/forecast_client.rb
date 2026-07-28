require "json"

module RubyWeather
  class ForecastClient
    ENDPOINT = "https://api.open-meteo.com/v1/forecast".freeze
    HOURLY = %w[
      temperature_2m
      relative_humidity_2m
      dew_point_2m
      precipitation_probability
      weather_code
      is_day
    ].freeze
    DAILY = %w[
      temperature_2m_min
      temperature_2m_max
      precipitation_probability_max
      weather_code
    ].freeze

    def initialize(transport:)
      @transport = transport
    end

    def call(location)
      JSON.parse(@transport.get(uri_for(location)))
    rescue JSON::ParserError => error
      raise ProviderError, "Invalid forecast response: #{error.message}"
    end

    private

    def uri_for(location)
      URI(ENDPOINT).tap do |uri|
        uri.query = URI.encode_www_form(
          latitude: location.latitude,
          longitude: location.longitude,
          elevation: location.elevation,
          timezone: location.timezone,
          temperature_unit: "fahrenheit",
          # Today's daily row uses 1 PM moisture, which may already be in the past.
          past_hours: 24,
          forecast_hours: 384,
          forecast_days: 16,
          hourly: HOURLY.join(","),
          daily: DAILY.join(",")
        )
      end
    end
  end
end
