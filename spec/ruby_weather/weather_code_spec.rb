require "spec_helper"

RSpec.describe "RubyWeather::WeatherCode" do
  let(:weather_code) { RubyWeather.const_get(:WeatherCode) }

  it "distinguishes clear day and night" do
    expect(weather_code.icon(0, day: true)).to eq("☀️")
    expect(weather_code.icon(0, day: false)).to eq("🌛")
  end

  it "maps rain and snow families and safely handles unknown codes" do
    expect(weather_code.precipitation_icon(63)).to eq("☔️")
    expect(weather_code.precipitation_icon(73)).to eq("❄️")
    expect(weather_code.icon(999, day: true)).to eq("❔")
  end
end
