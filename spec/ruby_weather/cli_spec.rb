require "spec_helper"
require "stringio"

RSpec.describe RubyWeather::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:now) { Time.utc(2026, 7, 28, 23, 24) }
  let(:clock) { -> { now } }
  let(:cache) { instance_double(RubyWeather::CacheStore) }
  let(:resolver) { instance_double(RubyWeather::LocationResolver) }
  let(:client) { instance_double(RubyWeather::ForecastClient) }
  let(:renderer) { instance_double(RubyWeather::Renderer) }
  let(:location) do
    RubyWeather::Location.new(
      query: "90210",
      name: "Audubon",
      admin1: "New Jersey",
      country: "United States",
      latitude: 39.89,
      longitude: -75.07,
      elevation: 20.0,
      timezone: "America/New_York"
    )
  end
  let(:payload) { JSON.parse(fixture("forecast/90210.json")) }
  let(:entry) do
    RubyWeather::CacheStore::Entry.new(
      location:,
      forecast_payload: payload,
      fetched_at: now - 60
    )
  end
  subject(:cli) do
    described_class.new(
      cache:,
      resolver:,
      forecast_client: client,
      renderer:,
      forecast_factory: RubyWeather::Forecast,
      clock:,
      stdout:,
      stderr:
    )
  end

  before do
    allow(resolver).to receive(:call)
    allow(client).to receive(:call)
    allow(renderer).to receive(:render).and_return("forecast\n")
  end

  it "renders a fresh cache entry without network access" do
    allow(cache).to receive(:read).with("90210").and_return(entry)
    allow(cache).to receive(:fresh?).with(entry, now:).and_return(true)

    expect(cli.call(["90210"])).to eq(0)
    expect(stdout.string).to eq("forecast\n")
    expect(resolver).not_to have_received(:call)
    expect(client).not_to have_received(:call)
  end

  it "rebuilds after a cache read miss" do
    allow(cache).to receive(:read).and_return(nil, nil)
    allow(cache).to receive(:with_lock).and_yield
    allow(cache).to receive(:write)
    allow(resolver).to receive(:call).with("90210").and_return(location)
    allow(client).to receive(:call).with(location).and_return(payload)

    expect(cli.call(["90210"])).to eq(0)
    expect(cache).to have_received(:write) do |query, written|
      expect(query).to eq("90210")
      expect(written.location).to eq(location)
      expect(written.forecast_payload).to eq(payload)
    end
  end

  it "accepts another process's fresh post-lock entry without fetching" do
    stale = entry.with(fetched_at: now - 3_600)
    fresh = entry.with(fetched_at: now - 30)
    allow(clock).to receive(:call).and_return(now)
    allow(cache).to receive(:read).and_return(stale, fresh)
    allow(cache).to receive(:fresh?).with(stale, now:).and_return(false)
    allow(cache).to receive(:fresh?).with(fresh, now:).and_return(true)
    allow(cache).to receive(:with_lock).and_yield

    expect(cli.call(["90210"])).to eq(0)
    expect(client).not_to have_received(:call)
    expect(clock).to have_received(:call).twice
  end

  it "forces a fetch despite a fresh cache entry" do
    allow(cache).to receive(:read).and_return(entry)
    allow(cache).to receive(:with_lock).and_yield
    allow(cache).to receive(:write)
    allow(client).to receive(:call).with(location).and_return(payload)

    expect(cli.call(["90210", "--force-fetch"])).to eq(0)
    expect(client).to have_received(:call).with(location)
  end

  it "warns with age and succeeds when refresh fails with usable stale data" do
    stale = entry.with(fetched_at: now - 7_200)
    allow(clock).to receive(:call).and_return(now)
    allow(cache).to receive(:read).and_return(stale, stale)
    allow(cache).to receive(:fresh?).with(stale, now:).and_return(false)
    allow(cache).to receive(:with_lock).and_yield
    allow(client).to receive(:call).with(location).and_raise(
      RubyWeather::ProviderError,
      "offline"
    )

    expect(cli.call(["90210"])).to eq(0)
    expect(stdout.string).to eq("forecast\n")
    expect(stderr.string).to match(/WARNING:.*2 hours ago/)
    expect(clock).to have_received(:call).exactly(3).times
  end

  it "fails without rendering when rebuild has no stale candidate" do
    allow(cache).to receive(:read).and_return(nil, nil)
    allow(cache).to receive(:with_lock).and_yield
    allow(resolver).to receive(:call).with("90210").and_raise(
      RubyWeather::ProviderError,
      "offline"
    )

    expect(cli.call(["90210"])).to eq(1)
    expect(renderer).not_to have_received(:render)
    expect(stderr.string).to include("offline")
  end

  it "treats an unnormalizable cached payload as a miss and rebuilds" do
    broken = entry.with(forecast_payload: {})
    allow(cache).to receive(:read).and_return(broken, broken)
    allow(cache).to receive(:with_lock).and_yield
    allow(cache).to receive(:write)
    allow(resolver).to receive(:call).with("90210").and_return(location)
    allow(client).to receive(:call).with(location).and_return(payload)

    expect(cli.call(["90210"])).to eq(0)
    expect(client).to have_received(:call).with(location)
  end

  it "passes provider and cache details only in verbose mode" do
    allow(cache).to receive(:read).and_return(entry)
    allow(cache).to receive(:fresh?).and_return(true)

    cli.call(["90210", "--verbose"])
    expect(renderer).to have_received(:render) do |arguments|
      expect(arguments.fetch(:metadata)).to include(
        "39.89",
        "-75.07",
        "api.open-meteo.com",
        "2026-07-28",
        "1 minute ago"
      )
    end

    cli.call(["90210"])
    expect(renderer).to have_received(:render).with(hash_including(metadata: nil))
  end

  it "uses conventional statuses and streams for help and usage errors" do
    expect(cli.call(["--help"])).to eq(0)
    expect(stdout.string).to include("Usage: rw LOCATION")
    expect(stderr.string).to eq("")

    stdout.truncate(0)
    stdout.rewind
    expect(cli.call([])).to eq(2)
    expect(stdout.string).to eq("")
    expect(stderr.string).to include("Usage: rw LOCATION")
  end
end
