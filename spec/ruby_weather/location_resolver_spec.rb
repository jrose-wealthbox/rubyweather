require "spec_helper"

RSpec.describe "RubyWeather::LocationResolver" do
  let(:resolver_class) { RubyWeather.const_get(:LocationResolver) }
  let(:transport) { instance_double("RubyWeather::HttpClient") }
  subject(:resolver) { resolver_class.new(transport:) }

  it "selects the first geocoding result and preserves the query" do
    allow(transport).to receive(:get).and_return(fixture("geocoding/90210.json"))

    location = resolver.call("90210")

    expect(location.display_name).to eq("Audubon, New Jersey, United States")
    expect(location.query).to eq("90210")
    expect(location.timezone).to eq("America/New_York")
    expect(transport).to have_received(:get) do |uri|
      expect(uri.host).to eq("geocoding-api.open-meteo.com")
      expect(uri.query).to include("name=90210", "count=10")
    end
  end

  it "raises a location error for no matches" do
    allow(transport).to receive(:get).and_return('{"results":[]}')

    expect { resolver.call("Nowhere") }
      .to raise_error(RubyWeather::LocationError, /No location found/)
  end

  it "rejects malformed geocoding responses" do
    allow(transport).to receive(:get).and_return('{"results":"wrong"}')

    expect { resolver.call("Nowhere") }
      .to raise_error(RubyWeather::ProviderError, /Invalid geocoding response/)
  end
end
