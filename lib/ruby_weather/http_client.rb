require "net/http"
require "uri"

module RubyWeather
  class HttpClient
    def get(uri)
      response = connection_for(uri).start do |connection|
        connection.get(uri.request_uri)
      end
      status = response.code.to_i
      unless (200..299).cover?(status)
        raise ProviderError, "Provider returned HTTP #{response.code}"
      end

      response.body
    rescue ProviderError
      raise
    rescue StandardError => error
      raise ProviderError, "Provider request failed: #{error.message}"
    end

    private

    def connection_for(uri)
      Net::HTTP.new(uri.host, uri.port).tap do |http|
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = Constants::HTTP_OPEN_TIMEOUT_SECONDS
        http.read_timeout = Constants::HTTP_READ_TIMEOUT_SECONDS
      end
    end
  end
end
