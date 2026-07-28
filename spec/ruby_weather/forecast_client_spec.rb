require "spec_helper"

RSpec.describe "RubyWeather::ForecastClient" do
  let(:client_class) { RubyWeather.const_get(:ForecastClient) }
  let(:transport) { instance_double("RubyWeather::HttpClient") }
  let(:location) do
    RubyWeather::Location.new(
      query: "08106",
      name: "Audubon",
      admin1: "New Jersey",
      country: "United States",
      latitude: 39.89,
      longitude: -75.07,
      elevation: 20.0,
      timezone: "America/New_York"
    )
  end

  it "requests full Fahrenheit coverage and all presentation fields" do
    allow(transport).to receive(:get).and_return(fixture("forecast/08106.json"))

    client_class.new(transport:).call(location)

    expect(transport).to have_received(:get) do |uri|
      params = URI.decode_www_form(uri.query).to_h
      expect(params).to include(
        "temperature_unit" => "fahrenheit",
        "timezone" => "America/New_York",
        "past_hours" => "24",
        "forecast_hours" => "384",
        "forecast_days" => "16"
      )
      expect(params.fetch("hourly").split(",")).to include(
        "temperature_2m",
        "relative_humidity_2m",
        "dew_point_2m",
        "precipitation_probability",
        "weather_code",
        "is_day"
      )
    end
  end

  it "rejects invalid JSON" do
    allow(transport).to receive(:get).and_return("{")

    expect { client_class.new(transport:).call(location) }
      .to raise_error(RubyWeather::ProviderError, /Invalid forecast response/)
  end
end
