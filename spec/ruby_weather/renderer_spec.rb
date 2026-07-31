require "spec_helper"

RSpec.describe "RubyWeather::Renderer" do
  let(:renderer_class) { RubyWeather.const_get(:Renderer) }
  let(:location) do
    instance_double(
      RubyWeather::Location,
      display_name: "Audubon, New Jersey, United States"
    )
  end
  let(:forecast) { instance_double(RubyWeather::Forecast) }
  let(:hour) do
    RubyWeather::Forecast::Hour.new(
      time: Time.new(2026, 7, 28, 19),
      temperature: 72.2,
      humidity: 45,
      dew_point: 65.1,
      precipitation_probability: 15,
      weather_code: 61,
      day: true
    )
  end
  let(:day) do
    RubyWeather::Forecast::Day.new(
      date: Date.new(2026, 7, 28),
      temperature_min: 62.1,
      temperature_max: 77.8,
      humidity: 45,
      dew_point: 65.1,
      precipitation_probability: 80,
      weather_code: 61
    )
  end

  before do
    allow(forecast).to receive(:hours).with(1).and_return([hour])
    allow(forecast).to receive(:days).with(1).and_return([day])
  end

  it "renders resolved location, weather tables, and attribution" do
    output = renderer_class.new.render(
      location:,
      forecast:,
      hours: 1,
      days: 1,
      metadata: nil
    )

    expect(output).to include("Audubon, New Jersey, United States")
    expect(output).to include("7PM", "🌧️ 72°", "45% (65°)", "☔️ 15%")
    expect(output).to include("Tue", "🌧️ 62°/78°", "☔️ 80%")
    expect(output).to end_with(
      "Weather data by Open-Meteo.com — https://open-meteo.com/\n"
    )
  end

  it "centers the hour and day headings within their columns" do
    output = renderer_class.new.render(
      location:,
      forecast:,
      hours: 1,
      days: 1,
      metadata: nil
    )

    expect(output).to include("          |    7PM\n")
    expect(output).to include("          |    Tue\n")
  end

  it "includes metadata only when supplied" do
    output = renderer_class.new.render(
      location:,
      forecast:,
      hours: 1,
      days: 1,
      metadata: "Fetched 1 minute ago"
    )

    expect(output).to include("Fetched 1 minute ago")
  end
end
