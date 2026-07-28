require "spec_helper"

RSpec.describe "RubyWeather::Forecast" do
  let(:forecast_class) { RubyWeather.const_get(:Forecast) }
  let(:payload) { JSON.parse(fixture("forecast/08106.json")) }
  let(:now) { Time.utc(2026, 7, 28, 23, 24) }

  it "starts hours at the current local forecast hour" do
    forecast = forecast_class.from_api(payload, now:)

    expect(forecast.hours(2).map { |hour| hour.time.strftime("%H:%M") })
      .to eq(%w[19:00 20:00])
  end

  it "uses exact 1 PM moisture and daily maximum precipitation" do
    day = forecast_class.from_api(payload, now:).days(1).first

    expect(day.date).to eq(Date.new(2026, 7, 28))
    expect(day.humidity).to eq(45)
    expect(day.dew_point).to eq(65.0)
    expect(day.precipitation_probability).to eq(80)
  end

  it "rejects inconsistent hourly arrays" do
    payload.fetch("hourly").fetch("temperature_2m").pop

    expect { forecast_class.from_api(payload, now:) }
      .to raise_error(RubyWeather::ProviderError, /hourly arrays/)
  end

  it "rejects malformed provider-local timestamps" do
    payload.fetch("hourly").transform_values! { |values| values.first(1) }
    payload.fetch("hourly")["time"] = ["not-a-time"]

    expect { forecast_class.from_api(payload, now:) }
      .to raise_error(RubyWeather::ProviderError, /Invalid local forecast time/)
  end

  it "rejects daily data without an exact 1 PM sample" do
    index = payload.fetch("hourly").fetch("time").index("2026-07-28T13:00")
    payload.fetch("hourly").each_value { |values| values.delete_at(index) }

    expect { forecast_class.from_api(payload, now:) }
      .to raise_error(RubyWeather::ProviderError, /Missing 1 PM forecast/)
  end
end
