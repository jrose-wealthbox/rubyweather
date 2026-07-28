require "spec_helper"
require "open3"
require "stringio"
require "tmpdir"

module IntegrationSupport
  class FixtureTransport
    attr_reader :requests

    def initialize(geocoding:, forecast:)
      @responses = {
        "geocoding-api.open-meteo.com" => geocoding,
        "api.open-meteo.com" => forecast
      }
      @requests = []
    end

    def get(uri)
      @requests << uri
      @responses.fetch(uri.host)
    end
  end
end

RSpec.describe "rw integration" do
  it "resolves, fetches, renders, then reuses the disk cache" do
    Dir.mktmpdir do |cache_root|
      transport = IntegrationSupport::FixtureTransport.new(
        geocoding: fixture("geocoding/90210.json"),
        forecast: fixture("forecast/90210.json")
      )
      stdout = StringIO.new
      stderr = StringIO.new
      cli = RubyWeather::CLI.default(
        stdout:,
        stderr:,
        transport:,
        cache_root:,
        clock: -> { Time.utc(2026, 7, 28, 23, 24) }
      )

      expect(cli.call(["90210", "--hours", "1", "--days", "1"])).to eq(0)
      expect(stdout.string).to include(
        "Audubon, New Jersey, United States",
        "Humidity",
        "Precip",
        "Weather data by Open-Meteo.com"
      )
      expect(stderr.string).to eq("")
      expect(transport.requests.map(&:host)).to eq(
        ["geocoding-api.open-meteo.com", "api.open-meteo.com"]
      )

      stdout.truncate(0)
      stdout.rewind
      expect(cli.call(["90210", "--hours", "1", "--days", "1"])).to eq(0)
      expect(transport.requests.length).to eq(2)
    end
  end

  it "routes executable help to stdout with status zero" do
    stdout, stderr, status = Open3.capture3(
      "bundle",
      "exec",
      "ruby",
      "-Ilib",
      "exe/rw",
      "--help"
    )

    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("Usage: rw LOCATION")
    expect(stderr).to eq("")
  end
end
