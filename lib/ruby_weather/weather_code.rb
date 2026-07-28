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
