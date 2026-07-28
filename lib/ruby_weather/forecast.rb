require "date"
require "time"

module RubyWeather
  class Forecast
    Hour = Data.define(
      :time,
      :temperature,
      :humidity,
      :dew_point,
      :precipitation_probability,
      :weather_code,
      :day
    )
    Day = Data.define(
      :date,
      :temperature_min,
      :temperature_max,
      :humidity,
      :dew_point,
      :precipitation_probability,
      :weather_code
    )

    def self.from_api(payload, now:)
      new(payload:, now:)
    rescue KeyError, ArgumentError, TypeError => error
      raise ProviderError, "Invalid forecast structure: #{error.message}"
    end

    def initialize(payload:, now:)
      @offset = Integer(payload.fetch("utc_offset_seconds"))
      @local_now = now.getlocal(@offset)
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
        @local_now.year,
        @local_now.month,
        @local_now.day,
        @local_now.hour,
        0,
        0,
        @offset
      )
    end

    def build_hours(hourly)
      arrays = fetch_arrays(
        hourly,
        %w[
          time temperature_2m relative_humidity_2m dew_point_2m
          precipitation_probability weather_code is_day
        ],
        "hourly"
      )
      arrays.fetch("time").each_index.map { |index| build_hour(arrays, index) }
    end

    def build_hour(arrays, index)
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

    def build_days(daily)
      arrays = fetch_arrays(
        daily,
        %w[
          time temperature_2m_min temperature_2m_max
          precipitation_probability_max weather_code
        ],
        "daily"
      )
      arrays.fetch("time").each_index.map { |index| build_day(arrays, index) }
    end

    def build_day(arrays, index)
      date = Date.iso8601(arrays["time"][index])
      afternoon = @hours.find { |hour| hour.time.to_date == date && hour.time.hour == 13 }
      raise ProviderError, "Missing 1 PM forecast for #{date}" unless afternoon

      Day.new(
        date:,
        temperature_min: arrays["temperature_2m_min"][index],
        temperature_max: arrays["temperature_2m_max"][index],
        humidity: afternoon.humidity,
        dew_point: afternoon.dew_point,
        precipitation_probability: arrays["precipitation_probability_max"][index],
        weather_code: arrays["weather_code"][index]
      )
    end

    def fetch_arrays(source, keys, label)
      arrays = keys.to_h { |key| [key, source.fetch(key)] }
      lengths = arrays.values.map(&:length).uniq
      raise ProviderError, "Inconsistent #{label} arrays" unless lengths.one?

      arrays
    end

    def parse_local_time(value)
      match = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})\z/.match(value)
      raise ProviderError, "Invalid local forecast time: #{value.inspect}" unless match

      Time.new(*match.captures.map(&:to_i), 0, @offset)
    end

    def ensure_coverage!(selected, count, label)
      if selected.length < count
        raise ProviderError, "Provider returned insufficient #{label} coverage"
      end

      selected
    end
  end
end
