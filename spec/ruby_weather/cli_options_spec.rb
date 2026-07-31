require "spec_helper"

RSpec.describe "RubyWeather::CLI" do
  let(:cli_class) { RubyWeather.const_get(:CLI) }

  describe ".parse" do
    it "uses the five-hour and five-day defaults" do
      options = cli_class.parse(["90210"])

      expect(options.to_h).to eq(
        location: "90210",
        hours: 5,
        days: 5,
        verbose: false,
        force_fetch: false
      )
    end

    it "accepts independent hour and day counts and switches" do
      options = cli_class.parse(
        ["Springfield, IL", "--hours", "10", "--days", "7", "--verbose", "--force-fetch"]
      )

      expect(options.to_h).to include(
        location: "Springfield, IL",
        hours: 10,
        days: 7,
        verbose: true,
        force_fetch: true
      )
    end

    it "validates hours against the shared maximum" do
      stub_const("RubyWeather::Constants::MAX_HOURS", 1)

      expect { cli_class.parse(["90210", "--hours", "2"]) }
        .to raise_error(RubyWeather::UsageError, /hours must be between 1 and 1/)
    end

    it "validates days against the shared maximum" do
      stub_const("RubyWeather::Constants::MAX_DAYS", 1)

      expect { cli_class.parse(["90210", "--days", "2"]) }
        .to raise_error(RubyWeather::UsageError, /days must be between 1 and 1/)
    end

    it "rejects missing locations, zero counts, and provider-overflow counts" do
      expect { cli_class.parse([]) }.to raise_error(RubyWeather::UsageError)
      expect { cli_class.parse(["90210", "--hours", "0"]) }
        .to raise_error(RubyWeather::UsageError, /hours must be between 1 and #{RubyWeather::Constants::MAX_HOURS}/)
      expect { cli_class.parse(["90210", "--days", "999"]) }
        .to raise_error(RubyWeather::UsageError, /days must be between 1 and #{RubyWeather::Constants::MAX_DAYS}/)
    end

    it "raises a successful help signal containing usage" do
      expect { cli_class.parse(["--help"]) }
        .to raise_error(RubyWeather::HelpRequested, /Usage: rw LOCATION/)
    end
  end
end
