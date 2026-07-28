# RubyWeather Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `rw` Ruby CLI that resolves a location, caches an Open-Meteo forecast, and prints five-hour and five-day weather tables with temperature, humidity, dew point, and precipitation.

**Architecture:** A small orchestration layer coordinates separately testable geocoding, forecast, normalization, cache, weather-code, and rendering objects. Provider JSON is cached atomically at full forecast coverage, then normalized before presentation; all time, HTTP, filesystem, and stream boundaries are injectable.

**Tech Stack:** Ruby 4.0-compatible standard library, Bundler, RSpec, RuboCop, `terminal-table` 4.x, and `unicode-display_width`.

## Global Constraints

- The application is a non-interactive macOS command that prints once and exits.
- `rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]` defaults to 5 hours and 5 days.
- Temperature and dew point are Fahrenheit-only.
- Open-Meteo is the only provider, and its attribution is always displayed.
- Forecasts are fresh for 30 minutes; all cache-read failures rebuild from the network.
- Stale data is rendered with an age warning when refresh fails.
- Ordinary concurrent invocations for one location must serialize refreshes with `flock`.
- Output does not wrap, truncate, rotate, or resize for terminal width.
- Runtime dependencies are limited to `terminal-table` and its transitive dependency.
- Tests make no live network requests.

---

## File Map

- `Gemfile`: Bundler entrypoint that loads the gemspec.
- `ruby_weather.gemspec`: executable, runtime dependency, and development dependency metadata.
- `Rakefile`: default RSpec task and RuboCop task.
- `.rubocop.yml`: focused lint configuration.
- `exe/rw`: thin executable that delegates to `RubyWeather::CLI`.
- `lib/ruby_weather.rb`: public requires and module namespace.
- `lib/ruby_weather/errors.rb`: typed user-facing failures.
- `lib/ruby_weather/http_client.rb`: timeout-bound `Net::HTTP` transport.
- `lib/ruby_weather/location.rb`: immutable resolved-location value.
- `lib/ruby_weather/location_resolver.rb`: Open-Meteo top-match geocoding.
- `lib/ruby_weather/forecast_client.rb`: Open-Meteo full-coverage forecast retrieval.
- `lib/ruby_weather/forecast.rb`: provider-array validation and normalized hour/day records.
- `lib/ruby_weather/cache_store.rb`: schema validation, freshness, advisory locking, and atomic writes.
- `lib/ruby_weather/weather_code.rb`: WMO condition, emoji, and precipitation-family mapping.
- `lib/ruby_weather/renderer.rb`: `terminal-table` output and metadata formatting.
- `lib/ruby_weather/cli.rb`: options, orchestration, fallbacks, streams, and exit statuses.
- `spec/spec_helper.rb`: deterministic RSpec configuration.
- `spec/support/fixture_helper.rb`: checked-in JSON fixture loader.
- `spec/fixtures/geocoding/08106.json`: representative top-match geocoding response.
- `spec/fixtures/forecast/08106.json`: 16-day representative provider response.
- `spec/**/*_spec.rb`: unit and integration coverage matching each responsibility.
- `README.md`: installation, usage, caching, attribution, and examples.

---

### Task 1: Package Skeleton, Errors, and Option Parsing

**Files:**
- Create: `Gemfile`
- Create: `ruby_weather.gemspec`
- Create: `Rakefile`
- Create: `.rubocop.yml`
- Create: `lib/ruby_weather.rb`
- Create: `lib/ruby_weather/errors.rb`
- Create: `lib/ruby_weather/cli.rb`
- Create: `spec/spec_helper.rb`
- Create: `spec/ruby_weather/cli_options_spec.rb`

**Interfaces:**
- Produces: `RubyWeather::UsageError < RubyWeather::Error`
- Produces: `RubyWeather::HelpRequested < RubyWeather::Error`
- Produces: `RubyWeather::CLI::Options = Data.define(:location, :hours, :days, :verbose, :force_fetch)`
- Produces: `RubyWeather::CLI.parse(argv) -> Options`

- [ ] **Step 1: Write the failing option-parser specs**

```ruby
# spec/ruby_weather/cli_options_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::CLI do
  describe ".parse" do
    it "uses the five-hour and five-day defaults" do
      options = described_class.parse(["08106"])

      expect(options.to_h).to eq(
        location: "08106",
        hours: 5,
        days: 5,
        verbose: false,
        force_fetch: false
      )
    end

    it "accepts independent hour and day counts and switches" do
      options = described_class.parse(
        ["Springfield, IL", "--hours", "12", "--days", "7", "--verbose", "--force-fetch"]
      )

      expect(options.to_h).to include(
        location: "Springfield, IL",
        hours: 12,
        days: 7,
        verbose: true,
        force_fetch: true
      )
    end

    it "rejects missing locations, zero counts, and provider-overflow counts" do
      expect { described_class.parse([]) }.to raise_error(RubyWeather::UsageError)
      expect { described_class.parse(["08106", "--hours", "0"]) }
        .to raise_error(RubyWeather::UsageError, /hours must be between 1 and 384/)
      expect { described_class.parse(["08106", "--days", "17"]) }
        .to raise_error(RubyWeather::UsageError, /days must be between 1 and 16/)
    end

    it "raises a successful help signal containing usage" do
      expect { described_class.parse(["--help"]) }
        .to raise_error(RubyWeather::HelpRequested, /Usage: rw LOCATION/)
    end
  end
end
```

- [ ] **Step 2: Add the package metadata and test harness**

```ruby
# ruby_weather.gemspec
Gem::Specification.new do |spec|
  spec.name = "ruby_weather"
  spec.version = "0.1.0"
  spec.summary = "Print an Open-Meteo forecast in the terminal"
  spec.authors = ["John"]
  spec.files = Dir["lib/**/*", "exe/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["rw"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.2"

  spec.add_dependency "terminal-table", "~> 4.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.75"
end
```

```ruby
# Gemfile
source "https://rubygems.org"
gemspec
```

```ruby
# Rakefile
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)
task default: %i[spec rubocop]
```

```yaml
# .rubocop.yml
AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  SuggestExtensions: false
Layout/LineLength:
  Max: 100
Metrics/BlockLength:
  Exclude:
    - "spec/**/*"
```

```ruby
# spec/spec_helper.rb
require "ruby_weather"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
```

- [ ] **Step 3: Run the option specs and verify the expected failure**

Run:

```sh
bundle install
bundle exec rspec spec/ruby_weather/cli_options_spec.rb
```

Expected: FAIL because `RubyWeather::CLI` does not exist.

- [ ] **Step 4: Implement typed errors and option parsing**

```ruby
# lib/ruby_weather/errors.rb
module RubyWeather
  class Error < StandardError; end
  class UsageError < Error; end
  class HelpRequested < Error; end
  class LocationError < Error; end
  class ProviderError < Error; end
end
```

```ruby
# lib/ruby_weather/cli.rb
require "optparse"

module RubyWeather
  class CLI
    Options = Data.define(:location, :hours, :days, :verbose, :force_fetch)

    def self.parse(argv)
      values = {hours: 5, days: 5, verbose: false, force_fetch: false}
      parser = OptionParser.new do |options|
        options.banner = "Usage: rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]"
        options.on("--hours N", Integer) { |value| values[:hours] = value }
        options.on("--days N", Integer) { |value| values[:days] = value }
        options.on("--verbose") { values[:verbose] = true }
        options.on("--force-fetch") { values[:force_fetch] = true }
        options.on("-h", "--help") { raise HelpRequested, options.to_s }
      end
      remaining = parser.parse(argv.dup)
      raise UsageError, parser.banner unless remaining.length == 1
      raise UsageError, "hours must be between 1 and 384" unless (1..384).cover?(values[:hours])
      raise UsageError, "days must be between 1 and 16" unless (1..16).cover?(values[:days])

      Options.new(location: remaining.first, **values)
    rescue OptionParser::ParseError => error
      raise UsageError, error.message
    end
  end
end
```

```ruby
# lib/ruby_weather.rb
require_relative "ruby_weather/errors"
require_relative "ruby_weather/cli"
```

- [ ] **Step 5: Run focused and aggregate checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/cli_options_spec.rb
bundle exec rubocop
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```sh
git add Gemfile Gemfile.lock ruby_weather.gemspec Rakefile .rubocop.yml lib spec
git commit -m "Set up RubyWeather CLI package"
```

---

### Task 2: HTTP Transport and Location Resolution

**Files:**
- Create: `lib/ruby_weather/http_client.rb`
- Create: `lib/ruby_weather/location.rb`
- Create: `lib/ruby_weather/location_resolver.rb`
- Create: `spec/fixtures/geocoding/08106.json`
- Create: `spec/support/fixture_helper.rb`
- Create: `spec/ruby_weather/http_client_spec.rb`
- Create: `spec/ruby_weather/location_resolver_spec.rb`
- Modify: `lib/ruby_weather.rb`
- Modify: `spec/spec_helper.rb`

**Interfaces:**
- Consumes: `RubyWeather::LocationError`, `RubyWeather::ProviderError`
- Produces: `HttpClient#get(uri) -> String`
- Produces: `Location.from_api(query:, attributes:) -> Location`
- Produces: `Location#to_h`, `Location.from_h(hash)`, and `Location#display_name`
- Produces: `LocationResolver#call(query) -> Location`

- [ ] **Step 1: Add fixture loading and failing resolver specs**

```ruby
# spec/support/fixture_helper.rb
module FixtureHelper
  def fixture(path)
    File.read(File.expand_path("../fixtures/#{path}", __dir__))
  end
end
```

```ruby
# spec/ruby_weather/location_resolver_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::LocationResolver do
  let(:transport) { instance_double(RubyWeather::HttpClient) }
  subject(:resolver) { described_class.new(transport:) }

  it "selects the first geocoding result and preserves the query" do
    allow(transport).to receive(:get).and_return(fixture("geocoding/08106.json"))

    location = resolver.call("08106")

    expect(location.display_name).to eq("Audubon, New Jersey, United States")
    expect(location.query).to eq("08106")
    expect(location.timezone).to eq("America/New_York")
    expect(transport).to have_received(:get) do |uri|
      expect(uri.host).to eq("geocoding-api.open-meteo.com")
      expect(uri.query).to include("name=08106", "count=10")
    end
  end

  it "raises a location error for no matches" do
    allow(transport).to receive(:get).and_return('{"results":[]}')

    expect { resolver.call("Nowhere") }
      .to raise_error(RubyWeather::LocationError, /No location found/)
  end
end
```

Create `spec/fixtures/geocoding/08106.json` from a saved Open-Meteo response
whose first result contains `name`, `admin1`, `country`, `latitude`,
`longitude`, `elevation`, and `timezone`.

- [ ] **Step 2: Write failing HTTP behavior specs**

```ruby
# spec/ruby_weather/http_client_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::HttpClient do
  it "wraps network failures as provider errors" do
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:start).and_raise(Timeout::Error, "timed out")

    expect { described_class.new.get(URI("https://example.test/data")) }
      .to raise_error(RubyWeather::ProviderError, /timed out/)
  end
end
```

- [ ] **Step 3: Run specs to verify failure**

Run:

```sh
bundle exec rspec spec/ruby_weather/http_client_spec.rb spec/ruby_weather/location_resolver_spec.rb
```

Expected: FAIL with missing `HttpClient` and `LocationResolver`.

- [ ] **Step 4: Implement transport, value object, and resolver**

```ruby
# lib/ruby_weather/http_client.rb
require "net/http"
require "uri"

module RubyWeather
  class HttpClient
    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10
      response = http.start { |connection| connection.get(uri.request_uri) }
      raise ProviderError, "Provider returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue ProviderError
      raise
    rescue StandardError => error
      raise ProviderError, "Provider request failed: #{error.message}"
    end
  end
end
```

```ruby
# lib/ruby_weather/location.rb
module RubyWeather
  Location = Data.define(
    :query, :name, :admin1, :country, :latitude, :longitude, :elevation, :timezone
  ) do
    def self.from_api(query:, attributes:)
      new(
        query:, name: attributes.fetch("name"), admin1: attributes["admin1"],
        country: attributes.fetch("country"), latitude: attributes.fetch("latitude"),
        longitude: attributes.fetch("longitude"), elevation: attributes["elevation"],
        timezone: attributes.fetch("timezone")
      )
    end

    def self.from_h(attributes)
      new(**attributes.transform_keys(&:to_sym))
    end

    def display_name
      [name, admin1, country].compact.reject(&:empty?).uniq.join(", ")
    end
  end
end
```

```ruby
# lib/ruby_weather/location_resolver.rb
require "json"

module RubyWeather
  class LocationResolver
    ENDPOINT = "https://geocoding-api.open-meteo.com/v1/search"

    def initialize(transport:)
      @transport = transport
    end

    def call(query)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(name: query, count: 10, language: "en", format: "json")
      result = JSON.parse(@transport.get(uri)).fetch("results", []).first
      raise LocationError, "No location found for #{query.inspect}" unless result

      Location.from_api(query:, attributes: result)
    rescue JSON::ParserError, KeyError => error
      raise ProviderError, "Invalid geocoding response: #{error.message}"
    end
  end
end
```

Update `lib/ruby_weather.rb` to require these files, and include
`config.include FixtureHelper` from `spec/support/fixture_helper` in
`spec/spec_helper.rb`.

- [ ] **Step 5: Run focused checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/http_client_spec.rb spec/ruby_weather/location_resolver_spec.rb
bundle exec rubocop
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```sh
git add lib/ruby_weather.rb lib/ruby_weather/http_client.rb lib/ruby_weather/location.rb \
  lib/ruby_weather/location_resolver.rb spec
git commit -m "Add Open-Meteo location resolution"
```

---

### Task 3: Forecast Retrieval and Normalization

**Files:**
- Create: `lib/ruby_weather/forecast_client.rb`
- Create: `lib/ruby_weather/forecast.rb`
- Create: `spec/fixtures/forecast/08106.json`
- Create: `spec/ruby_weather/forecast_client_spec.rb`
- Create: `spec/ruby_weather/forecast_spec.rb`
- Modify: `lib/ruby_weather.rb`

**Interfaces:**
- Consumes: `HttpClient#get`, `Location`
- Produces: `ForecastClient#call(location) -> Hash`
- Produces: `Forecast.from_api(payload, now:) -> Forecast`
- Produces: `Forecast#hours(count) -> Array<Hour>`
- Produces: `Forecast#days(count) -> Array<Day>`
- `Hour` fields: `time`, `temperature`, `humidity`, `dew_point`, `precipitation_probability`, `weather_code`, `day`
- `Day` fields: `date`, `temperature_min`, `temperature_max`, `humidity`, `dew_point`, `precipitation_probability`, `weather_code`

- [ ] **Step 1: Write failing forecast-client specs**

```ruby
# spec/ruby_weather/forecast_client_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::ForecastClient do
  let(:transport) { instance_double(RubyWeather::HttpClient) }
  let(:location) do
    RubyWeather::Location.new(
      query: "08106", name: "Audubon", admin1: "New Jersey", country: "United States",
      latitude: 39.89, longitude: -75.07, elevation: 20.0, timezone: "America/New_York"
    )
  end

  it "requests full Fahrenheit coverage and all presentation fields" do
    allow(transport).to receive(:get).and_return(fixture("forecast/08106.json"))

    described_class.new(transport:).call(location)

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
        "temperature_2m", "relative_humidity_2m", "dew_point_2m",
        "precipitation_probability", "weather_code", "is_day"
      )
    end
  end
end
```

- [ ] **Step 2: Write failing normalization specs**

```ruby
# spec/ruby_weather/forecast_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::Forecast do
  let(:payload) { JSON.parse(fixture("forecast/08106.json")) }
  let(:now) { Time.utc(2026, 7, 28, 23, 24) } # 7:24 PM at UTC-4

  it "starts hours at the current local forecast hour" do
    forecast = described_class.from_api(payload, now:)

    expect(forecast.hours(2).map { |hour| hour.time.strftime("%H:%M") })
      .to eq(%w[19:00 20:00])
  end

  it "uses exact 1 PM moisture and daily maximum precipitation" do
    forecast = described_class.from_api(payload, now:)
    day = forecast.days(1).first

    expect(day.date).to eq(Date.new(2026, 7, 28))
    expect(day.humidity).to eq(45)
    expect(day.dew_point).to eq(65.0)
    expect(day.precipitation_probability).to eq(
      payload.fetch("daily").fetch("precipitation_probability_max").first
    )
  end

  it "rejects inconsistent hourly arrays" do
    payload.fetch("hourly").fetch("temperature_2m").pop

    expect { described_class.from_api(payload, now:) }
      .to raise_error(RubyWeather::ProviderError, /hourly arrays/)
  end
end
```

Create `spec/fixtures/forecast/08106.json` as a compact checked-in fixture with
the exact fields above, `utc_offset_seconds: -14400`, hourly entries spanning
the test's current hour and 1 PM, and matching daily entries.

- [ ] **Step 3: Run specs and verify failure**

Run:

```sh
bundle exec rspec spec/ruby_weather/forecast_client_spec.rb spec/ruby_weather/forecast_spec.rb
```

Expected: FAIL with missing `ForecastClient` and `Forecast`.

- [ ] **Step 4: Implement the full-coverage request**

```ruby
# lib/ruby_weather/forecast_client.rb
require "json"

module RubyWeather
  class ForecastClient
    ENDPOINT = "https://api.open-meteo.com/v1/forecast"
    HOURLY = %w[
      temperature_2m relative_humidity_2m dew_point_2m
      precipitation_probability weather_code is_day
    ].freeze
    DAILY = %w[
      temperature_2m_min temperature_2m_max precipitation_probability_max weather_code
    ].freeze

    def initialize(transport:)
      @transport = transport
    end

    def call(location)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(
        latitude: location.latitude, longitude: location.longitude,
        elevation: location.elevation, timezone: location.timezone,
        temperature_unit: "fahrenheit",
        # Today's daily row always uses 1 PM moisture, which is already in the
        # past when this command runs later in the day.
        past_hours: 24, forecast_hours: 384, forecast_days: 16,
        hourly: HOURLY.join(","), daily: DAILY.join(",")
      )
      JSON.parse(@transport.get(uri))
    rescue JSON::ParserError => error
      raise ProviderError, "Invalid forecast response: #{error.message}"
    end
  end
end
```

- [ ] **Step 5: Implement strict normalization**

```ruby
# lib/ruby_weather/forecast.rb
require "date"
require "time"

module RubyWeather
  class Forecast
    Hour = Data.define(
      :time, :temperature, :humidity, :dew_point,
      :precipitation_probability, :weather_code, :day
    )
    Day = Data.define(
      :date, :temperature_min, :temperature_max, :humidity, :dew_point,
      :precipitation_probability, :weather_code
    )

    def self.from_api(payload, now:)
      new(payload:, now:)
    rescue KeyError, ArgumentError, TypeError => error
      raise ProviderError, "Invalid forecast structure: #{error.message}"
    end

    def initialize(payload:, now:)
      offset = Integer(payload.fetch("utc_offset_seconds"))
      @local_now = now.getlocal(offset)
      @hours = build_hours(payload.fetch("hourly"))
      @days = build_days(payload.fetch("daily"))
    end

    def hours(count)
      selected = @hours.drop_while { |hour| hour.time < current_hour }.first(count)
      ensure_coverage!(selected, count, "hourly")
    end

    def days(count)
      selected = @days.drop_while { |day| day.date < @local_now.to_date }.first(count)
      ensure_coverage!(selected, count, "daily")
    end

    private

    def current_hour
      Time.new(
        @local_now.year, @local_now.month, @local_now.day, @local_now.hour, 0, 0,
        @local_now.utc_offset
      )
    end

    def build_hours(hourly)
      keys = %w[
        time temperature_2m relative_humidity_2m dew_point_2m
        precipitation_probability weather_code is_day
      ]
      arrays = keys.to_h { |key| [key, hourly.fetch(key)] }
      lengths = arrays.values.map(&:length).uniq
      raise ProviderError, "Inconsistent hourly arrays" unless lengths.one?

      arrays.fetch("time").each_index.map do |index|
        Hour.new(
          time: parse_local_time(arrays["time"][index]),
          temperature: arrays["temperature_2m"][index],
          humidity: arrays["relative_humidity_2m"][index],
          dew_point: arrays["dew_point_2m"][index],
          precipitation_probability: arrays["precipitation_probability"][index],
          weather_code: arrays["weather_code"][index],
          day: arrays["is_day"][index] == 1
        )
      end
    end

    def parse_local_time(value)
      match = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})\z/.match(value)
      raise ProviderError, "Invalid local forecast time: #{value.inspect}" unless match

      Time.new(*match.captures.map(&:to_i), 0, @local_now.utc_offset)
    end

    def build_days(daily)
      keys = %w[
        time temperature_2m_min temperature_2m_max
        precipitation_probability_max weather_code
      ]
      arrays = keys.to_h { |key| [key, daily.fetch(key)] }
      lengths = arrays.values.map(&:length).uniq
      raise ProviderError, "Inconsistent daily arrays" unless lengths.one?

      arrays.fetch("time").each_index.map do |index|
        date = Date.iso8601(arrays["time"][index])
        afternoon = @hours.find { |hour| hour.time.to_date == date && hour.time.hour == 13 }
        raise ProviderError, "Missing 1 PM forecast for #{date}" unless afternoon

        Day.new(
          date:, temperature_min: arrays["temperature_2m_min"][index],
          temperature_max: arrays["temperature_2m_max"][index],
          humidity: afternoon.humidity, dew_point: afternoon.dew_point,
          precipitation_probability: arrays["precipitation_probability_max"][index],
          weather_code: arrays["weather_code"][index]
        )
      end
    end

    def ensure_coverage!(selected, count, label)
      raise ProviderError, "Provider returned insufficient #{label} coverage" if selected.length < count

      selected
    end
  end
end
```

Add this example without using the process-wide `TZ` environment variable:

```ruby
it "rejects malformed provider-local timestamps" do
  payload.fetch("hourly").transform_values! { |values| values.first(1) }
  payload.fetch("hourly")["time"] = ["not-a-time"]

  expect { described_class.from_api(payload, now:) }
    .to raise_error(RubyWeather::ProviderError, /Invalid local forecast time/)
end
```

- [ ] **Step 6: Run focused checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/forecast_client_spec.rb spec/ruby_weather/forecast_spec.rb
bundle exec rubocop
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit**

```sh
git add lib/ruby_weather.rb lib/ruby_weather/forecast_client.rb \
  lib/ruby_weather/forecast.rb spec
git commit -m "Normalize Open-Meteo forecasts"
```

---

### Task 4: Versioned, Locked, Atomic Cache

**Files:**
- Create: `lib/ruby_weather/cache_store.rb`
- Create: `spec/ruby_weather/cache_store_spec.rb`
- Modify: `lib/ruby_weather.rb`

**Interfaces:**
- Consumes: `Location#to_h`, `Location.from_h`
- Produces: `CacheStore::Entry = Data.define(:location, :forecast_payload, :fetched_at)`
- Produces: `CacheStore#read(query) -> Entry | nil`
- Produces: `CacheStore#write(query, entry) -> void`
- Produces: `CacheStore#fresh?(entry, now:) -> bool`
- Produces: `CacheStore#with_lock(query) { ... }`

- [ ] **Step 1: Write cache failure, freshness, and atomicity specs**

```ruby
# spec/ruby_weather/cache_store_spec.rb
require "spec_helper"
require "tmpdir"

RSpec.describe RubyWeather::CacheStore do
  let(:root) { Dir.mktmpdir }
  let(:store) { described_class.new(root:) }
  let(:location) do
    RubyWeather::Location.new(
      query: "08106", name: "Audubon", admin1: "New Jersey", country: "United States",
      latitude: 39.89, longitude: -75.07, elevation: 20.0, timezone: "America/New_York"
    )
  end
  let(:entry) do
    described_class::Entry.new(
      location:, forecast_payload: {"utc_offset_seconds" => -14_400},
      fetched_at: Time.utc(2026, 7, 28, 12)
    )
  end

  after { FileUtils.remove_entry(root) }

  it "round trips a versioned entry and applies a strict 30-minute lifetime" do
    store.write("08106", entry)

    loaded = store.read("08106")
    expect(loaded.location).to eq(location)
    expect(store.fresh?(loaded, now: entry.fetched_at + 1_800)).to be true
    expect(store.fresh?(loaded, now: entry.fetched_at + 1_801)).to be false
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

  it "leaves no temporary files after atomic replacement" do
    store.write("08106", entry)
    expect(Dir.children(root).grep(/tmp/)).to be_empty
    expect(JSON.parse(File.read(store.path_for("08106"))).fetch("schema_version")).to eq(1)
  end
end
```

- [ ] **Step 2: Run the spec and verify failure**

Run:

```sh
bundle exec rspec spec/ruby_weather/cache_store_spec.rb
```

Expected: FAIL with missing `CacheStore`.

- [ ] **Step 3: Implement fail-open reads, locking, and atomic writes**

```ruby
# lib/ruby_weather/cache_store.rb
require "digest"
require "fileutils"
require "json"
require "tempfile"
require "time"

module RubyWeather
  class CacheStore
    SCHEMA_VERSION = 1
    MAX_AGE = 30 * 60
    Entry = Data.define(:location, :forecast_payload, :fetched_at)

    def initialize(root:)
      @root = root
    end

    def path_for(query)
      File.join(@root, "#{key(query)}.json")
    end

    def read(query)
      data = JSON.parse(File.read(path_for(query)))
      return unless data.fetch("schema_version") == SCHEMA_VERSION

      Entry.new(
        location: Location.from_h(data.fetch("location")),
        forecast_payload: data.fetch("forecast_payload"),
        fetched_at: Time.iso8601(data.fetch("fetched_at"))
      )
    rescue StandardError
      nil
    end

    def fresh?(entry, now:)
      now - entry.fetched_at <= MAX_AGE
    end

    def with_lock(query)
      FileUtils.mkdir_p(@root)
      File.open(File.join(@root, "#{key(query)}.lock"), File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      ensure
        file&.flock(File::LOCK_UN)
      end
    end

    def write(query, entry)
      FileUtils.mkdir_p(@root)
      payload = {
        schema_version: SCHEMA_VERSION,
        location: entry.location.to_h,
        forecast_payload: entry.forecast_payload,
        fetched_at: entry.fetched_at.iso8601
      }
      Tempfile.create(["rubyweather-", ".tmp"], @root) do |file|
        file.write(JSON.generate(payload))
        file.flush
        file.fsync
        File.rename(file.path, path_for(query))
      end
    end

    private

    def key(query)
      Digest::SHA256.hexdigest(query.strip.downcase)
    end
  end
end
```

The broad `StandardError` rescue in `read` is intentional: the approved cache
contract treats permissions, decoding, schema, and structure failures
identically as misses and rebuilds from the source.

- [ ] **Step 4: Verify locking across two real processes**

```ruby
it "serializes two processes refreshing the same location" do
  events_reader, events_writer = IO.pipe
  release_reader, release_writer = IO.pipe

  first = fork do
    events_reader.close
    release_writer.close
    store.with_lock("08106") do
      events_writer.puts("first-acquired")
      release_reader.gets
      events_writer.puts("first-released")
    end
  end
  expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("first-acquired")

  second = fork do
    events_reader.close
    release_reader.close
    store.with_lock("08106") { events_writer.puts("second-acquired") }
  end

  expect(IO.select([events_reader], nil, nil, 0.1)).to be_nil
  release_writer.puts("release")
  expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("first-released")
  expect(Timeout.timeout(2) { events_reader.gets.chomp }).to eq("second-acquired")
ensure
  [first, second].compact.each { |pid| Process.wait(pid) }
  [events_reader, events_writer, release_reader, release_writer].compact.each(&:close)
end
```

Require `timeout` at the top of the spec. The short `IO.select` assertion is
the only timing-sensitive portion; the two-second guards prevent a broken lock
from hanging the suite.

- [ ] **Step 5: Run focused checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/cache_store_spec.rb
bundle exec rubocop
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```sh
git add lib/ruby_weather.rb lib/ruby_weather/cache_store.rb spec/ruby_weather/cache_store_spec.rb
git commit -m "Add resilient forecast cache"
```

---

### Task 5: Weather-Code Mapping and Table Rendering

**Files:**
- Create: `lib/ruby_weather/weather_code.rb`
- Create: `lib/ruby_weather/renderer.rb`
- Create: `spec/ruby_weather/weather_code_spec.rb`
- Create: `spec/ruby_weather/renderer_spec.rb`
- Modify: `lib/ruby_weather.rb`

**Interfaces:**
- Consumes: normalized `Hour`, `Day`, `Location`
- Produces: `WeatherCode.icon(code, day:) -> String`
- Produces: `WeatherCode.precipitation_icon(code) -> String`
- Produces: `Renderer#render(location:, forecast:, hours:, days:, metadata:) -> String`

- [ ] **Step 1: Write weather-code specs**

```ruby
# spec/ruby_weather/weather_code_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::WeatherCode do
  it "distinguishes clear day and night" do
    expect(described_class.icon(0, day: true)).to eq("☀️")
    expect(described_class.icon(0, day: false)).to eq("🌛")
  end

  it "maps rain and snow families and safely handles unknown codes" do
    expect(described_class.precipitation_icon(63)).to eq("☔️")
    expect(described_class.precipitation_icon(73)).to eq("❄️")
    expect(described_class.icon(999, day: true)).to eq("❔")
  end
end
```

- [ ] **Step 2: Write an exact rendering spec**

```ruby
# spec/ruby_weather/renderer_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::Renderer do
  it "renders resolved location, hourly and daily tables, and attribution" do
    forecast = instance_double(RubyWeather::Forecast)
    allow(forecast).to receive(:hours).with(1).and_return([
      RubyWeather::Forecast::Hour.new(
        time: Time.new(2026, 7, 28, 19), temperature: 72.2, humidity: 45,
        dew_point: 65.1, precipitation_probability: 15, weather_code: 61, day: true
      )
    ])
    allow(forecast).to receive(:days).with(1).and_return([
      RubyWeather::Forecast::Day.new(
        date: Date.new(2026, 7, 28), temperature_min: 62.1, temperature_max: 77.8,
        humidity: 45, dew_point: 65.1, precipitation_probability: 80, weather_code: 61
      )
    ])
    location = instance_double(RubyWeather::Location, display_name: "Audubon, New Jersey, United States")

    output = described_class.new.render(
      location:, forecast:, hours: 1, days: 1, metadata: nil
    )

    expect(output).to include("Audubon, New Jersey, United States")
    expect(output).to include("7PM", "☔️ 72°", "45% (65°)", "☔️ 15%")
    expect(output).to include("Tue", "☔️ 62°/78°", "☔️ 80%")
    expect(output).to end_with(
      "Weather data by Open-Meteo.com — https://open-meteo.com/\n"
    )
  end
end
```

- [ ] **Step 3: Run specs and verify failure**

Run:

```sh
bundle exec rspec spec/ruby_weather/weather_code_spec.rb spec/ruby_weather/renderer_spec.rb
```

Expected: FAIL with missing `WeatherCode` and `Renderer`.

- [ ] **Step 4: Implement deterministic WMO mapping**

```ruby
# lib/ruby_weather/weather_code.rb
module RubyWeather
  module WeatherCode
    module_function

    def icon(code, day:)
      case code
      when 0 then day ? "☀️" : "🌛"
      when 1, 2 then "🌤️"
      when 3, 45, 48 then "☁️"
      when 51..67, 80..82, 95..99 then "🌧️"
      when 71..77, 85, 86 then "🌨️"
      else "❔"
      end
    end

    def precipitation_icon(code)
      case code
      when 51..67, 80..82, 95..99 then "☔️"
      when 71..77, 85, 86 then "❄️"
      else ""
      end
    end
  end
end
```

- [ ] **Step 5: Implement compact `terminal-table` rendering**

```ruby
# lib/ruby_weather/renderer.rb
require "terminal-table"

module RubyWeather
  class Renderer
    ATTRIBUTION = "Weather data by Open-Meteo.com — https://open-meteo.com/"

    def render(location:, forecast:, hours:, days:, metadata:)
      parts = [
        location.display_name,
        hourly_table(forecast.hours(hours)),
        daily_table(forecast.days(days))
      ]
      parts << metadata if metadata
      parts << ATTRIBUTION
      "#{parts.join("\n\n")}\n"
    end

    private

    def hourly_table(hours)
      table(
        ["", *hours.map { |hour| hour.time.strftime("%-I%p") }],
        [
          ["Temp", *hours.map { |hour| temperature_cell(hour) }],
          ["Humidity", *hours.map { |hour| humidity_cell(hour) }],
          ["Precip", *hours.map { |hour| precip_cell(hour) }]
        ]
      )
    end

    def daily_table(days)
      table(
        ["", *days.map { |day| day.date.strftime("%a") }],
        [
          ["Temp", *days.map { |day| temperature_range_cell(day) }],
          ["Humidity", *days.map { |day| humidity_cell(day) }],
          ["Precip", *days.map { |day| precip_cell(day) }]
        ]
      )
    end

    def table(headings, rows)
      result = Terminal::Table.new(headings:, rows:)
      result.style = {
        border_top: false, border_bottom: false,
        border_left: false, border_right: false
      }
      (1...headings.length).each { |column| result.align_column(column, :right) }
      result.to_s
    end

    def precip_cell(record)
      [WeatherCode.precipitation_icon(record.weather_code),
       "#{round(record.precipitation_probability)}%"].reject(&:empty?).join(" ")
    end

    def temperature_cell(hour)
      "#{WeatherCode.icon(hour.weather_code, day: hour.day)} #{round(hour.temperature)}°"
    end

    def temperature_range_cell(day)
      icon = WeatherCode.icon(day.weather_code, day: true)
      "#{icon} #{round(day.temperature_min)}°/#{round(day.temperature_max)}°"
    end

    def humidity_cell(record)
      "#{round(record.humidity)}% (#{round(record.dew_point)}°)"
    end

    def round(value)
      Float(value).round
    end
  end
end
```

- [ ] **Step 6: Run focused checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/weather_code_spec.rb spec/ruby_weather/renderer_spec.rb
bundle exec rubocop
```

Expected: both commands exit 0 and the snapshot uses stable Unicode widths.

- [ ] **Step 7: Commit**

```sh
git add lib/ruby_weather.rb lib/ruby_weather/weather_code.rb \
  lib/ruby_weather/renderer.rb spec/ruby_weather
git commit -m "Render weather forecast tables"
```

---

### Task 6: CLI Orchestration, Refresh, and Stale Fallback

**Files:**
- Modify: `lib/ruby_weather/cli.rb`
- Create: `exe/rw`
- Create: `spec/ruby_weather/cli_spec.rb`
- Modify: `lib/ruby_weather.rb`

**Interfaces:**
- Consumes: all prior task interfaces
- Produces: `CLI#call(argv) -> Integer`
- Produces: `CLI.default(stdout:, stderr:) -> CLI`
- Produces: executable exit statuses 0, 1, and 2

- [ ] **Step 1: Write orchestration specs for cache hits and rebuilds**

```ruby
# spec/ruby_weather/cli_spec.rb
require "spec_helper"

RSpec.describe RubyWeather::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:clock) { -> { Time.utc(2026, 7, 28, 23, 24) } }
  let(:cache) { instance_double(RubyWeather::CacheStore) }
  let(:resolver) { instance_double(RubyWeather::LocationResolver) }
  let(:client) { instance_double(RubyWeather::ForecastClient) }
  let(:renderer) { instance_double(RubyWeather::Renderer) }
  let(:location) { instance_double(RubyWeather::Location) }
  let(:forecast) { instance_double(RubyWeather::Forecast) }
  let(:entry) do
    RubyWeather::CacheStore::Entry.new(
      location:, forecast_payload: {"valid" => true}, fetched_at: clock.call - 60
    )
  end
  subject(:cli) do
    described_class.new(
      cache:, resolver:, forecast_client: client, renderer:,
      forecast_factory: RubyWeather::Forecast, clock:, stdout:, stderr:
    )
  end

  it "renders a fresh cache entry without network access" do
    allow(cache).to receive(:read).with("08106").and_return(entry)
    allow(cache).to receive(:fresh?).with(entry, now: clock.call).and_return(true)
    allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
    allow(renderer).to receive(:render).and_return("forecast\n")

    expect(cli.call(["08106"])).to eq(0)
    expect(stdout.string).to eq("forecast\n")
    expect(resolver).not_to have_received(:call)
  end

  it "rebuilds after any cache read miss" do
    allow(cache).to receive(:read).and_return(nil)
    allow(cache).to receive(:with_lock).and_yield
    allow(resolver).to receive(:call).and_return(location)
    allow(client).to receive(:call).and_return("valid" => true)
    allow(cache).to receive(:write)
    allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
    allow(renderer).to receive(:render).and_return("forecast\n")

    expect(cli.call(["08106"])).to eq(0)
    expect(client).to have_received(:call).with(location)
    expect(cache).to have_received(:write)
  end
end
```

- [ ] **Step 2: Add stale, force, post-lock, and stream specs**

```ruby
it "warns with age and succeeds when refresh fails with usable stale data" do
  allow(cache).to receive(:read).and_return(entry)
  allow(cache).to receive(:fresh?).and_return(false)
  allow(cache).to receive(:with_lock).and_yield
  allow(client).to receive(:call).and_raise(RubyWeather::ProviderError, "offline")
  allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
  allow(renderer).to receive(:render).and_return("stale\n")

  expect(cli.call(["08106"])).to eq(0)
  expect(stdout.string).to eq("stale\n")
  expect(stderr.string).to match(/WARNING:.*1 minute ago/)
end

it "returns usage status 2 and provider status 1 on stderr" do
  expect(cli.call([])).to eq(2)
  expect(stderr.string).to include("Usage: rw")
end
```

Add these concrete examples:

```ruby
it "accepts another process's fresh post-lock entry without fetching" do
  stale = entry.with(fetched_at: clock.call - 3_600)
  fresh = entry.with(fetched_at: clock.call - 30)
  allow(cache).to receive(:read).and_return(stale, fresh)
  allow(cache).to receive(:fresh?).with(stale, now: clock.call).and_return(false)
  allow(cache).to receive(:fresh?).with(fresh, now: clock.call).and_return(true)
  allow(cache).to receive(:with_lock).and_yield
  allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
  allow(renderer).to receive(:render).and_return("forecast\n")

  expect(cli.call(["08106"])).to eq(0)
  expect(client).not_to have_received(:call)
end

it "forces a fetch despite fresh pre-lock and post-lock entries" do
  allow(cache).to receive(:read).and_return(entry)
  allow(cache).to receive(:fresh?).and_return(true)
  allow(cache).to receive(:with_lock).and_yield
  allow(client).to receive(:call).with(location).and_return("valid" => true)
  allow(cache).to receive(:write)
  allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
  allow(renderer).to receive(:render).and_return("forecast\n")

  expect(cli.call(["08106", "--force-fetch"])).to eq(0)
  expect(client).to have_received(:call).with(location)
end

it "fails without rendering when cache rebuild has no stale candidate" do
  allow(cache).to receive(:read).and_return(nil)
  allow(cache).to receive(:with_lock).and_yield
  allow(resolver).to receive(:call).and_raise(RubyWeather::ProviderError, "offline")

  expect(cli.call(["08106"])).to eq(1)
  expect(renderer).not_to have_received(:render)
  expect(stderr.string).to include("offline")
end
```

```ruby
it "passes provider and cache details only in verbose mode" do
  allow(cache).to receive(:read).and_return(entry)
  allow(cache).to receive(:fresh?).and_return(true)
  allow(RubyWeather::Forecast).to receive(:from_api).and_return(forecast)
  allow(location).to receive_messages(latitude: 39.89, longitude: -75.07)
  allow(renderer).to receive(:render).and_return("forecast\n")

  cli.call(["08106", "--verbose"])
  expect(renderer).to have_received(:render) do |arguments|
    expect(arguments.fetch(:metadata)).to include(
      "39.89", "-75.07", "api.open-meteo.com", "2026-07-28", "1 minute ago"
    )
  end

  cli.call(["08106"])
  expect(renderer).to have_received(:render).with(hash_including(metadata: nil))
end
```

- [ ] **Step 3: Run the CLI specs and verify failure**

Run:

```sh
bundle exec rspec spec/ruby_weather/cli_spec.rb
```

Expected: FAIL because `CLI#call` and dependency injection are not implemented.

- [ ] **Step 4: Implement orchestration with post-lock recheck**

Implement `CLI#call` around this exact control flow:

```ruby
def call(argv)
  options = self.class.parse(argv)
  now = @clock.call
  entry, forecast = readable_entry(options.location, now:)

  unless options.force_fetch
    return render(options, entry, forecast, now:) if entry && @cache.fresh?(entry, now:)
  end

  @cache.with_lock(options.location) do
    unless options.force_fetch
      locked_entry, locked_forecast = readable_entry(options.location, now: @clock.call)
      if locked_entry && @cache.fresh?(locked_entry, now: @clock.call)
        return render(options, locked_entry, locked_forecast, now: @clock.call)
      end
      entry, forecast = locked_entry, locked_forecast
    end

    begin
      location = entry&.location || @resolver.call(options.location)
      payload = @forecast_client.call(location)
      fetched_at = @clock.call
      refreshed = CacheStore::Entry.new(
        location:, forecast_payload: payload, fetched_at:
      )
      normalized = @forecast_factory.from_api(payload, now: fetched_at)
      @cache.write(options.location, refreshed)
      render(options, refreshed, normalized, now: fetched_at)
    rescue Error => error
      raise unless entry && forecast

      warn_stale(error, entry, now: @clock.call)
      render(options, entry, forecast, now: @clock.call)
    end
  end
rescue UsageError => error
  @stderr.puts(error.message)
  2
rescue HelpRequested => help
  @stdout.puts(help.message)
  0
rescue Error => error
  @stderr.puts("Error: #{error.message}")
  1
rescue StandardError => error
  @stderr.puts("Error: unexpected failure: #{error.message}")
  1
end
```

`readable_entry` must call both `cache.read` and `Forecast.from_api`; if either
returns nil/raises for cached data, it returns `[nil, nil]`. This is what makes
schema upgrades, malformed payloads, and filesystem failures rebuild instead
of becoming stale candidates.

Use this default cache root:

```ruby
File.join(Dir.home, "Library", "Caches", "rubyweather")
```

Use dependency construction only in `CLI.default`; tests continue to call the
initializer directly.

- [ ] **Step 5: Add the thin executable**

```ruby
#!/usr/bin/env ruby
# exe/rw
require "ruby_weather"

exit RubyWeather::CLI.default(stdout: $stdout, stderr: $stderr).call(ARGV)
```

Run:

```sh
chmod +x exe/rw
```

- [ ] **Step 6: Run focused and full checks**

Run:

```sh
bundle exec rspec spec/ruby_weather/cli_spec.rb spec/ruby_weather/cli_options_spec.rb
bundle exec rake
```

Expected: all specs and RuboCop pass.

- [ ] **Step 7: Commit**

```sh
git add exe/rw lib/ruby_weather.rb lib/ruby_weather/cli.rb spec/ruby_weather/cli_spec.rb
git commit -m "Wire RubyWeather command workflow"
```

---

### Task 7: End-to-End Contract, Documentation, and Final Verification

**Files:**
- Create: `spec/integration/rw_spec.rb`
- Create: `README.md`

**Interfaces:**
- Consumes: installed `rw` executable and all prior public interfaces
- Produces: documented user contract and release-ready test suite

- [ ] **Step 1: Write a subprocess integration test**

```ruby
# spec/integration/rw_spec.rb
require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "rw integration" do
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

  it "resolves, fetches, renders, then reuses the disk cache" do
    Dir.mktmpdir do |cache_root|
      transport = FixtureTransport.new(
        geocoding: fixture("geocoding/08106.json"),
        forecast: fixture("forecast/08106.json")
      )
      stdout = StringIO.new
      stderr = StringIO.new
      cli = RubyWeather::CLI.default(
        stdout:, stderr:, transport:, cache_root:,
        clock: -> { Time.utc(2026, 7, 28, 23, 24) }
      )

      expect(cli.call(["08106", "--hours", "1", "--days", "1"])).to eq(0)
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
      expect(cli.call(["08106", "--hours", "1", "--days", "1"])).to eq(0)
      expect(transport.requests.length).to eq(2)
    end
  end

  it "routes executable help to stdout with status zero" do
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-Ilib", "exe/rw", "--help"
    )

    expect(status.exitstatus).to eq(0)
    expect(stdout).to include("Usage: rw LOCATION")
    expect(stderr).to eq("")
  end
end
```

- [ ] **Step 2: Run the integration test and verify failure**

Run:

```sh
bundle exec rspec spec/integration/rw_spec.rb
```

Expected: FAIL until the test composition seam and executable environment are
connected.

- [ ] **Step 3: Implement only the test composition seam**

Allow `CLI.default` to accept these optional keyword overrides while preserving
production defaults:

```ruby
def self.default(stdout:, stderr:, transport: HttpClient.new, clock: -> { Time.now },
                 cache_root: File.join(Dir.home, "Library", "Caches", "rubyweather"))
```

Do not add environment-variable configuration to production behavior.

- [ ] **Step 4: Write the user README**

Document these exact examples:

```sh
bundle install
bundle exec exe/rw 08106
bundle exec exe/rw "Springfield, IL" --hours 12 --days 7
bundle exec exe/rw 08106 --verbose --force-fetch
```

Explain:

- Defaults are 5 hours and 5 days.
- Fahrenheit is fixed.
- The first Open-Meteo geocoding result is selected.
- Forecasts are cached for 30 minutes under
  `~/Library/Caches/rubyweather/`.
- Corrupt or incompatible caches are automatically rebuilt.
- Failed refreshes show stale data with a warning when possible.
- Wide requests are intentionally not wrapped.
- Open-Meteo attribution and non-commercial terms apply.

- [ ] **Step 5: Verify the dependency graph**

Run:

```sh
bundle lock
bundle exec ruby -e 'puts Gem.loaded_specs.values.map(&:name).grep(/terminal|unicode/).sort'
```

Expected runtime table dependencies:

```text
terminal-table
unicode-display_width
```

- [ ] **Step 6: Run the complete verification suite**

Run:

```sh
bundle exec rspec
bundle exec rubocop
bundle exec ruby -Ilib exe/rw --help
git diff --check
```

Expected:

- All specs pass.
- RuboCop reports no offenses.
- Help exits 0 and displays the usage line.
- `git diff --check` emits no output.

- [ ] **Step 7: Perform one optional live smoke test**

This step requires network access and must not run in the deterministic suite:

```sh
bundle exec ruby -Ilib exe/rw 08106 --hours 2 --days 2 --verbose --force-fetch
```

Expected:

- Resolved location is printed.
- Two hourly and two daily columns are printed.
- Humidity cells include parenthesized dew points.
- Verbose metadata and attribution are printed.
- A second non-forced invocation reports cached data and makes no forecast
  refresh.

- [ ] **Step 8: Commit**

```sh
git add README.md Gemfile.lock lib spec
git commit -m "Document and verify RubyWeather"
```

---

## Plan Completion Criteria

- Every requirement in
  `docs/superpowers/specs/2026-07-28-rubyweather-design.md` is implemented or
  explicitly covered by a non-goal.
- The deterministic suite passes without network access.
- A corrupted, unreadable, or old-schema cache triggers a fetch and atomic
  replacement.
- A usable stale forecast is rendered with an age warning after refresh
  failure.
- Concurrent ordinary invocations cannot duplicate a refresh for one location.
- `terminal-table` output remains aligned for the checked-in emoji fixtures.
- The worktree is clean after the final commit.
