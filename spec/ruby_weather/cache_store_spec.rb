require "spec_helper"
require "fileutils"
require "io/wait"
require "tmpdir"
require "timeout"

RSpec.describe "RubyWeather::CacheStore" do
  let(:store_class) { RubyWeather.const_get(:CacheStore) }
  let(:root) { Dir.mktmpdir }
  let(:store) { store_class.new(root:) }
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
  let(:entry) do
    store_class::Entry.new(
      location:,
      forecast_payload: { "utc_offset_seconds" => -14_400 },
      fetched_at: Time.utc(2026, 7, 28, 12)
    )
  end

  after { FileUtils.rm_rf(root) }

  it "round trips a versioned entry and applies a strict 30-minute lifetime" do
    store.write("08106", entry)

    loaded = store.read("08106")
    expect(loaded.location).to eq(location)
    expect(loaded.forecast_payload).to eq(entry.forecast_payload)
    expect(store.fresh?(loaded, now: entry.fetched_at + 1_800)).to be(true)
    expect(store.fresh?(loaded, now: entry.fetched_at + 1_801)).to be(false)
  end

  it "treats invalid JSON and unsupported schemas as cache misses" do
    FileUtils.mkdir_p(root)
    File.write(store.path_for("08106"), "{broken")
    expect(store.read("08106")).to be_nil

    File.write(store.path_for("08106"), JSON.generate("schema_version" => 999))
    expect(store.read("08106")).to be_nil
  end

  it "treats filesystem read failures as cache misses" do
    allow(File).to receive(:read).and_raise(Errno::EACCES)

    expect(store.read("08106")).to be_nil
  end

  it "uses a digest rather than user input in cache paths" do
    expect(store.path_for("../../escape")).to start_with(root)
    expect(File.basename(store.path_for("../../escape"))).to match(/\A[0-9a-f]{64}\.json\z/)
  end

  it "leaves no temporary files after atomic replacement" do
    store.write("08106", entry)

    expect(Dir.children(root).grep(/\.tmp\z/)).to be_empty
    expect(JSON.parse(File.read(store.path_for("08106"))).fetch("schema_version")).to eq(1)
  end

  it "serializes two processes refreshing the same location" do
    cache_store = store
    events_reader, events_writer = IO.pipe
    release_reader, release_writer = IO.pipe

    first = fork do
      events_reader.close
      release_writer.close
      cache_store.with_lock("08106") do
        events_writer.puts("first-acquired")
        release_reader.gets
        events_writer.puts("first-released")
      end
    end
    expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("first-acquired")

    second = fork do
      events_reader.close
      release_reader.close
      cache_store.with_lock("08106") { events_writer.puts("second-acquired") }
    end

    expect(events_reader.wait_readable(0.1)).to be_nil
    release_writer.puts("release")
    expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("first-released")
    expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("second-acquired")
  ensure
    [first, second].compact.each { |pid| Process.wait(pid) }
    [events_reader, events_writer, release_reader, release_writer].compact.each do |io|
      io.close unless io.closed?
    end
  end
end
