module RubyWeather
  Location = Data.define(
    :query,
    :name,
    :admin1,
    :country,
    :latitude,
    :longitude,
    :elevation,
    :timezone
  ) do
    def self.from_api(query:, attributes:)
      new(
        query:,
        name: attributes.fetch("name"),
        admin1: attributes["admin1"],
        country: attributes.fetch("country"),
        latitude: attributes.fetch("latitude"),
        longitude: attributes.fetch("longitude"),
        elevation: attributes["elevation"],
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
