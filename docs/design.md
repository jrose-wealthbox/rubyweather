# RubyWeather Design

## Sample usage and output

`rw` - name of script
`90210` - location to use
`5` - number of hours and days to list

```
bundle exec rw 90210 5 --verbose --force-fetch
```

```
         |   7PM   |   8PM   |   9PM   |   10PM  |   11PM   
Temp     |    ☀️ 72|    🌤️ 72|    🌧️ 45|    🌨️ 32|    🌛 72         
Humidity | 45% (65)| 55% (64)| 47% (65)| 45% (65)| 45% (65)
Precip   |       0%|       0%|   ☔️ 15%|   ❄️ 20%|       0%


         |     Mon    |     Tue    |     Wed    |     Thu    |     Fri    
Temp     |  🌧️ 32°/72°|  🌧️ 32°/72°|  ☀️ 32°/72°|  ☀️ 32°/72°|  ☀️ 32°/72°   
Humidity |   45% (65°)|   45% (65°)|   45% (65°)|   45% (65°)|   45% (65°) 
Precip   |     ☔️ 100%|     ❄️ 100%|        100%|        100%|        100% 

Fetched 24 minutes ago from http://api.sample.whereever
```

`45% (65°)` is humidity and dew point

For the hourly forecase, humidity and dew point should be for that hour (obviously)

For the daily forcast, humidity and dew point should be the values for 1PM on that day

`Fetched 24 minutes ago from http://api.sample.whereever` should only be displayed if `--verbose` is supplied

`rw` exits after printing the weather, does not stay running

## Architecture

- Responses from the API should be cached on disk. Always read from the on-disk file, unless it is more than 30 minutes old. We should be able to run `rw` 100 times a minute without generating more than 2 API calls per hour
- If `--force-fetch` is specified, always read from the API source even if we have a fresh cache file
- Use a gem to generate the output tables, consider https://github.com/tj/terminal-table or similar
- create a gemfile w/ the appropriate gems
- Program should be small and lean (a few hundred lines at most?)
- Cleanly separate the fetch logic and the format logic