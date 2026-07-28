# RubyWeather

RubyWeather (`rw`) prints an hourly and daily Open-Meteo forecast and exits.
It is a small, non-interactive Ruby command intended for personal use on macOS.

The tables show:

- Temperature
- Relative humidity with dew point in parentheses
- Precipitation probability

Temperatures are displayed in Fahrenheit.

## Setup

```sh
bundle install
```

Run the repository-local executable:

```sh
bundle exec exe/rw 90210
```

When installed as a gem, the executable is simply:

```sh
rw 90210
```

## Usage

```text
rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]
```

Examples:

```sh
bundle exec exe/rw 90210
bundle exec exe/rw "Springfield, IL" --hours 12 --days 7
bundle exec exe/rw 90210 --verbose --force-fetch
```

The defaults are five hours and five days. `LOCATION` may be a place name or
postal code. RubyWeather automatically uses Open-Meteo's first geocoding match;
include a state, region, or country to disambiguate names.

`--verbose` displays the resolved coordinates, provider endpoint, fetch time,
and cache age. `--force-fetch` requests a refresh even when cached data is
fresh.

RubyWeather intentionally does not wrap or truncate wide tables. Large
`--hours` and `--days` values may exceed the terminal width.

## Cache

Forecasts are cached for 30 minutes under:

```text
~/Library/Caches/rubyweather/
```

Concurrent invocations for the same location share an advisory file lock so
only one ordinary refresh occurs at cache expiration.

Unreadable, corrupt, incomplete, or old-schema cache entries are discarded and
rebuilt from Open-Meteo. Successful refreshes replace cache files atomically.

If a refresh fails and the previous forecast is still readable, RubyWeather
prints the stale forecast with a warning containing its age. If no usable
forecast exists, it prints an error and exits nonzero.

## Data source

Weather and location data come from Open-Meteo:

- https://open-meteo.com/en/docs
- https://open-meteo.com/en/docs/geocoding-api

The free API is used under Open-Meteo's non-commercial terms. Attribution is
always displayed in command output:

```text
Weather data by Open-Meteo.com — https://open-meteo.com/
```
