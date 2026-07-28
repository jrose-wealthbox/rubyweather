require "optparse"

module RubyWeather
  class CLI
    Options = Data.define(:location, :hours, :days, :verbose, :force_fetch)

    def self.default(
      stdout:,
      stderr:,
      transport: HttpClient.new,
      clock: -> { Time.now },
      cache_root: File.join(Dir.home, "Library", "Caches", "rubyweather")
    )
      new(
        cache: CacheStore.new(root: cache_root),
        resolver: LocationResolver.new(transport:),
        forecast_client: ForecastClient.new(transport:),
        renderer: Renderer.new,
        forecast_factory: Forecast,
        clock:,
        stdout:,
        stderr:
      )
    end

    def self.parse(argv)
      values = { hours: 5, days: 5, verbose: false, force_fetch: false }
      parser = OptionParser.new do |options|
        options.banner = usage
        options.on("--hours N", Integer) { |value| values[:hours] = value }
        options.on("--days N", Integer) { |value| values[:days] = value }
        options.on("--verbose") { values[:verbose] = true }
        options.on("--force-fetch") { values[:force_fetch] = true }
        options.on("-h", "--help") { raise HelpRequested, options.to_s }
      end
      remaining = parser.parse(argv.dup)
      raise UsageError, parser.banner unless remaining.length == 1
      raise UsageError, "hours must be between 1 and 10" unless (1..10).cover?(values[:hours])
      raise UsageError, "days must be between 1 and 10" unless (1..10).cover?(values[:days])

      Options.new(location: remaining.first, **values)
    rescue OptionParser::ParseError => error
      raise UsageError, error.message
    end

    def self.usage
      "Usage: rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]"
    end

    def initialize(
      cache:,
      resolver:,
      forecast_client:,
      renderer:,
      forecast_factory:,
      clock:,
      stdout:,
      stderr:
    )
      @cache = cache
      @resolver = resolver
      @forecast_client = forecast_client
      @renderer = renderer
      @forecast_factory = forecast_factory
      @clock = clock
      @stdout = stdout
      @stderr = stderr
    end

    def call(argv)
      options = self.class.parse(argv)
      now = @clock.call
      entry, forecast = readable_entry(options.location, now:)

      if !options.force_fetch && entry && @cache.fresh?(entry, now:)
        return render(options, entry, forecast, now:)
      end

      refresh_locked(options, entry, forecast)
    rescue HelpRequested => error
      @stdout.puts(error.message)
      0
    rescue UsageError => error
      @stderr.puts(error.message)
      2
    rescue Error => error
      @stderr.puts("Error: #{error.message}")
      1
    rescue StandardError => error
      @stderr.puts("Error: unexpected failure: #{error.message}")
      1
    end

    private

    def refresh_locked(options, entry, forecast)
      @cache.with_lock(options.location) do
        unless options.force_fetch
          entry, forecast = readable_entry(options.location, now: @clock.call)
          if entry && @cache.fresh?(entry, now: @clock.call)
            return render(options, entry, forecast, now: @clock.call)
          end
        end

        refresh(options, entry, forecast)
      end
    end

    def refresh(options, stale_entry, stale_forecast)
      location = stale_entry&.location || @resolver.call(options.location)
      payload = @forecast_client.call(location)
      fetched_at = @clock.call
      forecast = @forecast_factory.from_api(payload, now: fetched_at)
      entry = CacheStore::Entry.new(location:, forecast_payload: payload, fetched_at:)
      @cache.write(options.location, entry)
      render(options, entry, forecast, now: fetched_at)
    rescue Error => error
      raise unless stale_entry && stale_forecast

      warn_stale(error, stale_entry, now: @clock.call)
      render(options, stale_entry, stale_forecast, now: @clock.call)
    end

    def readable_entry(location, now:)
      entry = @cache.read(location)
      return [nil, nil] unless entry

      [entry, @forecast_factory.from_api(entry.forecast_payload, now:)]
    rescue ProviderError
      [nil, nil]
    end

    def render(options, entry, forecast, now:)
      @stdout.write(
        @renderer.render(
          location: entry.location,
          forecast:,
          hours: options.hours,
          days: options.days,
          metadata: metadata(options, entry, now:)
        )
      )
      0
    end

    def metadata(options, entry, now:)
      return unless options.verbose

      [
        "Coordinates: #{entry.location.latitude}, #{entry.location.longitude}",
        "Provider: #{ForecastClient::ENDPOINT}",
        "Fetched: #{entry.fetched_at.iso8601}",
        "Cache age: #{human_age(entry, now:)}"
      ].join("\n")
    end

    def warn_stale(error, entry, now:)
      @stderr.puts(
        "WARNING: Open-Meteo refresh failed (#{error.message}); " \
        "showing forecast fetched #{human_age(entry, now:)}."
      )
    end

    def human_age(entry, now:)
      seconds = [now - entry.fetched_at, 0].max.to_i
      return "less than a minute ago" if seconds < 60

      minutes = seconds / 60
      return quantity(minutes, "minute") if minutes < 60

      hours = minutes / 60
      return quantity(hours, "hour") if hours < 24

      quantity(hours / 24, "day")
    end

    def quantity(value, unit)
      suffix = "s" unless value == 1
      "#{value} #{unit}#{suffix} ago"
    end
  end
end
