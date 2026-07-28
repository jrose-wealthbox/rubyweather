# RubyWeather Design

## Purpose

RubyWeather is a small, non-interactive Ruby command-line application for
personal use on macOS. It resolves a user-supplied place, fetches an Open-Meteo
forecast, prints hourly and daily weather tables, and exits.

The useful moisture measurements are first-class output:

- Temperature
- Relative humidity
- Dew point
- Precipitation probability

The application is intentionally lean. It has one command, one weather
provider, a disk cache, and no persistent process.

## Command-Line Interface

During development, invoke the repository-local executable with:

```sh
bundle exec exe/rw 08106
```

Once installed as a gem, invoke it with:

```sh
rw 08106
```

The full interface is:

```text
rw LOCATION [--hours N] [--days N] [--verbose] [--force-fetch]
```

`LOCATION` is a required positional string. It may be a postal code or place
name. Shell quoting is required when it contains spaces.

Options:

- `--hours N` displays the next N hourly periods. The default is 5.
- `--days N` displays N daily periods, beginning with today. The default is 5.
- `--verbose` displays provider, coordinates, fetch time, and cache age.
- `--force-fetch` attempts a forecast refresh even when the cache is fresh.
- `--help` displays usage and exits successfully.

Hours and days must be positive integers within the forecast coverage returned
by Open-Meteo. The initial supported limits are 384 hours and 16 days. RubyWeather
reports invalid arguments before making a network request.

Temperature and dew point are displayed in Fahrenheit. Unit selection is
deliberately out of scope.

RubyWeather does not adapt output to terminal width. A caller who requests a
large forecast accepts wide output.

## Location Resolution

RubyWeather uses the Open-Meteo Geocoding API to resolve `LOCATION`.

The application:

1. Normalizes the query for cache lookup without changing the displayed input.
2. Requests matching locations when no cached resolution exists.
3. Selects Open-Meteo's first result without prompting.
4. Displays the resolved city, administrative region when present, and country.
5. Caches the resolved coordinates, elevation, and IANA timezone.

Users disambiguate places by supplying more context, such as
`"Springfield, IL"`. An empty result is an error.

Resolved locations do not expire with forecasts. `--force-fetch` refreshes
weather, not geocoding. Deleting the cache causes location resolution to run
again.

## Weather Provider

Open-Meteo is the only initial provider. It requires no API key for
non-commercial personal use and supplies the required hourly measurements.

The forecast request uses:

- The resolved latitude, longitude, and elevation
- The resolved timezone
- Fahrenheit temperature units
- Full supported hourly and daily coverage, independent of the requested
  display counts

Requested hourly fields:

- `temperature_2m`
- `relative_humidity_2m`
- `dew_point_2m`
- `precipitation_probability`
- `weather_code`
- `is_day`

Requested daily fields:

- `temperature_2m_min`
- `temperature_2m_max`
- `precipitation_probability_max`
- `weather_code`

Fetching full coverage makes one cached response reusable across invocations
with different `--hours` and `--days` values. The renderer slices the cached
data; CLI display choices do not fragment the cache.

Open-Meteo returns dew point directly. RubyWeather does not synthesize dew
point in the initial implementation. A future provider may calculate it from
temperature and relative humidity behind the normalized forecast boundary.

The client uses explicit connect/read timeouts and accepts only successful HTTP
responses with the expected JSON shape. Redirects, transport failures,
non-success statuses, invalid JSON, and inconsistent parallel arrays are
provider failures.

## Normalized Forecast

Provider-shaped parallel arrays are converted into records before rendering.
The renderer never indexes raw Open-Meteo arrays.

An hourly record contains:

- Local timestamp
- Temperature
- Relative humidity
- Dew point
- Precipitation probability
- WMO weather code
- Day/night indicator

A daily record contains:

- Local calendar date
- Minimum and maximum temperature
- Maximum precipitation probability
- Daily WMO weather code
- The hourly humidity and dew point at 1:00 PM local time

The hourly display begins with the current local forecast hour. The daily
display begins with the location's current local date, not the computer's
calendar date.

If an exact 1:00 PM hourly record is absent, normalization fails rather than
silently substituting another time. This prevents the displayed value from
having an ambiguous meaning.

Numeric values are rounded to whole display units at the formatting boundary,
not while normalizing or caching.

## Presentation

Every successful invocation prints:

1. The resolved location
2. The hourly table
3. A blank line
4. The daily table
5. Any stale-data warning
6. Verbose metadata when requested
7. Open-Meteo attribution

The hourly table has forecast times as column headings and these metric rows:

- `Temp`: weather emoji and temperature
- `Humidity`: relative humidity and parenthesized dew point
- `Precip`: precipitation probability and a precipitation indicator when
  applicable

The daily table has abbreviated weekdays as column headings and these rows:

- `Temp`: daily weather emoji and minimum/maximum temperature
- `Humidity`: 1:00 PM relative humidity and parenthesized dew point
- `Precip`: the day's maximum precipitation probability and precipitation
  indicator when applicable

An example humidity cell is:

```text
45% (65°)
```

Weather emojis are a deterministic mapping from WMO weather codes. Rain and
snow precipitation indicators follow the code's precipitation family. Unknown
codes use a neutral fallback rather than raising.

Attribution is always visible:

```text
Weather data by Open-Meteo.com — https://open-meteo.com/
```

Verbose metadata includes the resolved coordinates, the provider endpoint,
the fetch timestamp, and a human-readable cache age. Provider query URLs must
not contain secrets; Open-Meteo's selected API does not use credentials.

## Table Renderer Decision

RubyWeather uses `terminal-table` 4.x.

It is fit for this output because it supports:

- Tables represented as arrays of rows
- Headings
- Per-column and per-cell alignment
- Configurable separators and borders
- Unicode table content
- Display width through its single runtime dependency,
  `unicode-display_width`

The renderer disables or customizes borders to stay close to the compact sample
output. It does not request terminal-width resizing.

`TTY::Table` was rejected because its additional resizing, rotation, color, and
terminal-screen capabilities are unnecessary here; its latest released gem is
also older and brings more runtime dependencies. A custom renderer was rejected
because correct emoji-aware padding would recreate the main value supplied by
`terminal-table`.

No library can guarantee identical emoji width across every terminal and font.
Tests establish expected output under the selected
`unicode-display_width` version, while minor environment-specific glyph
differences are acceptable.

## Cache

The cache root is:

```text
~/Library/Caches/rubyweather/
```

Tests inject a temporary cache root. Cache filenames are derived safely from a
normalized location query; user input is never used directly as a path.

Each location entry contains:

- A cache schema version
- Original location query
- Resolved location metadata
- Raw forecast response
- Forecast fetch timestamp

Forecasts remain fresh for 30 minutes. A fresh, structurally valid cache entry
avoids all network calls.

Refreshes are coordinated with a per-location advisory file lock. After
acquiring the lock, an invocation rechecks the cache because another process
may have refreshed it while this process waited. `--force-fetch` deliberately
does not accept another process's fresh result as satisfying its requested
refresh.

When a refresh succeeds, RubyWeather writes a temporary file in the cache
directory and atomically renames it over the prior entry. This preserves the
last usable forecast if the process is interrupted during serialization.

Any cache-read failure is treated as a cache miss. This includes filesystem
errors, invalid JSON, an unsupported schema version, missing fields, and a
forecast payload that cannot be normalized safely. RubyWeather then performs a
normal fetch and atomically replaces the entry. An unreadable or invalid entry
is not eligible for stale fallback; if rebuilding also fails, the command exits
with the fetch error.

The lock covers freshness rechecking, refresh, and atomic replacement, so many
concurrent ordinary invocations at a cache boundary still produce only one
refresh. Repeated explicit `--force-fetch` invocations are exempt from the
rate-saving guarantee because each one requests network access.

## Refresh and Stale Fallback

Normal behavior:

1. Use a fresh valid cache entry.
2. Otherwise resolve the location if necessary and fetch a forecast.
3. Cache and render a successful response.

`--force-fetch` skips step 1 but otherwise follows the same behavior.

If a refresh fails and a normalizable cached forecast exists, RubyWeather:

- Renders the stale forecast
- Prints a warning regardless of `--verbose`
- Includes the human-readable age in the warning
- Exits successfully because it produced explicitly qualified output

Example:

```text
WARNING: Open-Meteo refresh failed; showing forecast fetched 2 hours ago.
```

If no usable cached forecast exists, RubyWeather prints a concise error to
stderr and exits nonzero.

## Errors and Exit Status

Expected user-facing failures do not print Ruby backtraces.

- Exit 0: fresh output, refreshed output, or explicitly warned stale output
- Exit 2: invalid command-line usage
- Exit 1: location, network, provider-response, cache-without-fallback, or
  unexpected application failure

Normal tables and verbose metadata go to stdout. Warnings and errors go to
stderr. `--help` goes to stdout.

The outer executable catches known application errors separately from
unexpected exceptions. Unexpected failures receive a concise message by
default; development tests retain the original exception as the cause.

## Structure

The initial code is organized around these responsibilities:

- `RubyWeather::CLI`: option parsing, orchestration, output streams, exit status
- `RubyWeather::LocationResolver`: Open-Meteo geocoding and top-match selection
- `RubyWeather::ForecastClient`: Open-Meteo forecast request and response checks
- `RubyWeather::CacheStore`: lookup, validation, freshness, and atomic writes
- `RubyWeather::Forecast`: normalized hourly and daily records
- `RubyWeather::Renderer`: table construction and metadata formatting
- `RubyWeather::WeatherCode`: WMO code-to-condition and emoji mapping

HTTP transport, clock, cache root, and output streams are injected where they
cross system boundaries. Internal value records remain simple immutable data
objects.

There is no generic provider plugin framework. The normalized forecast boundary
is enough to permit a second provider later without designing abstractions for
unknown requirements now.

## Dependencies

Runtime:

- Ruby standard library: `optparse`, `net/http`, `json`, `uri`, `time`,
  `digest`, `fileutils`, and date/time support
- `terminal-table` 4.x

Development:

- RSpec
- RuboCop

Additional CLI, HTTP, dependency injection, caching, and time libraries are out
of scope unless implementation uncovers a concrete deficiency.

## Testing

The test suite makes no live network requests. It injects the transport, clock,
cache root, and output streams and uses checked-in provider fixtures.

Required coverage:

- CLI defaults, overrides, help, and invalid counts
- Automatic top-match location resolution
- Empty and malformed geocoding responses
- Forecast URL construction and requested fields
- Successful provider-response normalization
- Missing fields, invalid JSON, inconsistent arrays, and non-success responses
- Current-hour selection in the resolved timezone
- Daily selection using the location's date
- Exact 1:00 PM humidity and dew-point selection
- Daily maximum precipitation probability
- Weather-code and precipitation-indicator mapping
- Day/night clear-sky icon selection
- Fresh cache hits with zero network calls
- Concurrent refresh serialization and the post-lock freshness recheck
- Expired and forced refreshes
- Atomic cache replacement
- Malformed and unsupported cache entries
- Filesystem cache-read failures followed by cache rebuild
- Refresh failure with stale fallback and age warning
- Refresh failure without a usable fallback
- Exact stdout/stderr separation and exit statuses
- Representative table snapshots containing emoji

Integration-style CLI tests exercise the executable with faked HTTP responses
and a temporary cache. Unit tests cover normalization, freshness boundaries,
and rendering without invoking a subprocess.

## Explicit Non-Goals

- Interactive location selection
- Continuous refresh or a long-running TUI event loop
- Metric units or configurable units
- Terminal-width wrapping, truncation, or scrolling
- Weather alerts, wind, pressure, radar, or historical weather
- Multiple weather providers in the initial release
- Config files or environment-based user preferences
- Commercial operation or removal of required attribution

## References

- Open-Meteo Forecast API: https://open-meteo.com/en/docs
- Open-Meteo Geocoding API: https://open-meteo.com/en/docs/geocoding-api
- Open-Meteo license: https://open-meteo.com/en/license
- terminal-table: https://github.com/tj/terminal-table
