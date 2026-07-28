require "spec_helper"
require "net/http"

RSpec.describe "RubyWeather::HttpClient" do
  let(:client_class) { RubyWeather.const_get(:HttpClient) }

  it "returns the body for successful responses" do
    response = instance_double(Net::HTTPSuccess, body: '{"ok":true}', code: "200")
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start).and_yield(http)
    allow(http).to receive(:get).and_return(response)

    expect(client_class.new.get(URI("https://example.test/data"))).to eq('{"ok":true}')
  end

  it "wraps network failures as provider errors" do
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start).and_raise(Timeout::Error, "timed out")

    expect { client_class.new.get(URI("https://example.test/data")) }
      .to raise_error(RubyWeather::ProviderError, /timed out/)
  end

  it "rejects unsuccessful HTTP responses" do
    response = instance_double(Net::HTTPBadGateway, code: "502")
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start).and_yield(http)
    allow(http).to receive(:get).and_return(response)

    expect { client_class.new.get(URI("https://example.test/data")) }
      .to raise_error(RubyWeather::ProviderError, /HTTP 502/)
  end
end
