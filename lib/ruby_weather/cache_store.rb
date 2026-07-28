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
      # Cache data is disposable. Any filesystem, parsing, or schema failure
      # becomes a miss so the caller can rebuild it from Open-Meteo.
      nil
    end

    def fresh?(entry, now:)
      now - entry.fetched_at <= MAX_AGE
    end

    def with_lock(query)
      FileUtils.mkdir_p(@root)
      File.open(lock_path(query), File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        yield
      ensure
        file&.flock(File::LOCK_UN)
      end
    end

    def write(query, entry)
      FileUtils.mkdir_p(@root)
      Tempfile.create(["rubyweather-", ".tmp"], @root) do |file|
        file.write(JSON.generate(serialized(entry)))
        file.flush
        file.fsync
        File.rename(file.path, path_for(query))
      end
    end

    private

    def serialized(entry)
      {
        schema_version: SCHEMA_VERSION,
        location: entry.location.to_h,
        forecast_payload: entry.forecast_payload,
        fetched_at: entry.fetched_at.iso8601
      }
    end

    def lock_path(query)
      File.join(@root, "#{key(query)}.lock")
    end

    def key(query)
      Digest::SHA256.hexdigest(query.strip.downcase)
    end
  end
end
