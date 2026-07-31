require "terminal-table"

module RubyWeather
  class Renderer
    ATTRIBUTION = "Weather data by Open-Meteo.com — https://open-meteo.com/".freeze

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
        ["", *hours.map { |hour| centered_heading(hour.time.strftime("%-I%p")) }],
        [
          ["Temp", *hours.map { |hour| temperature_cell(hour) }],
          ["Humidity", *hours.map { |hour| humidity_cell(hour) }],
          ["Precip", *hours.map { |hour| precipitation_cell(hour) }]
        ]
      )
    end

    def daily_table(days)
      table(
        ["", *days.map { |day| centered_heading(day.date.strftime("%a")) }],
        [
          ["Temp", *days.map { |day| temperature_range_cell(day) }],
          ["Humidity", *days.map { |day| humidity_cell(day) }],
          ["Precip", *days.map { |day| precipitation_cell(day) }]
        ]
      )
    end

    def table(headings, rows)
      Terminal::Table.new(headings:, rows:).tap do |table|
        table.style = {
          border_top: false,
          border_bottom: false,
          border_left: false,
          border_right: false
        }
        (1...headings.length).each { |column| table.align_column(column, :right) }
      end.to_s
    end

    def centered_heading(value)
      { value:, alignment: :center }
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

    def precipitation_cell(record)
      icon = WeatherCode.precipitation_icon(record.weather_code)
      [icon, "#{round(record.precipitation_probability)}%"].reject(&:empty?).join(" ")
    end

    def round(value)
      Float(value).round
    end
  end
end
