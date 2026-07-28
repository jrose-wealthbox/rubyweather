require "optparse"

module RubyWeather
  class CLI
    Options = Data.define(:location, :hours, :days, :verbose, :force_fetch)

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
      raise UsageError, "hours must be between 1 and 384" unless (1..384).cover?(values[:hours])
      raise UsageError, "days must be between 1 and 16" unless (1..16).cover?(values[:days])

      Options.new(location: remaining.first, **values)
    rescue OptionParser::ParseError => error
      raise UsageError, error.message
    end

    def self.usage
      "Usage: rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]"
    end
  end
end
