require "spec_helper"

RSpec.describe "RubyWeather::CLI" do
  let(:cli_class) { RubyWeather.const_get(:CLI) }

  describe ".parse" do
    it "uses the five-hour and five-day defaults" do
      options = cli_class.parse(["08106"])

      expect(options.to_h).to eq(
        location: "08106",
        hours: 5,
        days: 5,
        verbose: false,
        force_fetch: false
      )
    end

    it "accepts independent hour and day counts and switches" do
      options = cli_class.parse(
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
      expect { cli_class.parse([]) }.to raise_error(RubyWeather::UsageError)
      expect { cli_class.parse(["08106", "--hours", "0"]) }
        .to raise_error(RubyWeather::UsageError, /hours must be between 1 and 384/)
      expect { cli_class.parse(["08106", "--days", "17"]) }
        .to raise_error(RubyWeather::UsageError, /days must be between 1 and 16/)
    end

    it "raises a successful help signal containing usage" do
      expect { cli_class.parse(["--help"]) }
        .to raise_error(RubyWeather::HelpRequested, /Usage: rw LOCATION/)
    end
  end
end
