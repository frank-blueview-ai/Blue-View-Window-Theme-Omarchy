#!/bin/bash
# Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
# Licensed under the PolyForm Noncommercial License 1.0.0.
# Blue View OS screensaver: current weather, sky and 7-day forecast as one JSON line.
# Current conditions and sun/moon times come from wttr.in (the location Omarchy's
# weather widget uses); the 7-day forecast comes from Open-Meteo for that spot.

place=$(omarchy-weather-location 2>/dev/null)
query=$(jq -rn --arg place "$place" '$place | @uri')

unit=C
curl -fsS --max-time 5 "https://wttr.in/${query}?format=%t" 2>/dev/null | grep -q F && unit=F

wttr=$(curl -fsS --max-time 10 "https://wttr.in/${query}?format=j1" 2>/dev/null) || exit 1

read -r lat lon < <(jq -r '.nearest_area[0] | "\(.latitude) \(.longitude)"' <<<"$wttr")
temperature_unit=$([[ $unit == F ]] && echo fahrenheit || echo celsius)
forecast=$(curl -fsS --max-time 10 "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&daily=weather_code,temperature_2m_max,temperature_2m_min&temperature_unit=${temperature_unit}&timezone=auto&forecast_days=7" 2>/dev/null)
[[ -n $forecast ]] || forecast=null

jq -ce --arg unit "$unit" --arg place "$place" --argjson forecast "$forecast" '
  # "06:12 AM" -> minutes after midnight, null for "No moonrise" and the like.
  def minutes: try (capture("(?<h>[0-9]+):(?<m>[0-9]+) (?<p>[AP]M)") | ((.h | tonumber) % 12 + (if .p == "PM" then 12 else 0 end)) * 60 + (.m | tonumber)) catch null;
  def trim: gsub("^\\s+|\\s+$"; "");
  # WMO weather code -> the equivalent wttr.in code, so one icon/sky mapping serves both.
  def wttrCode: {
    "0": 113, "1": 116, "2": 116, "3": 122, "45": 248, "48": 260,
    "51": 266, "53": 266, "55": 266, "56": 281, "57": 284,
    "61": 296, "63": 302, "65": 308, "66": 311, "67": 314,
    "71": 326, "73": 332, "75": 338, "77": 179,
    "80": 353, "81": 356, "82": 359, "85": 368, "86": 371,
    "95": 389, "96": 395, "99": 395
  }[tostring] // 119;
  .current_condition[0] as $now
  | .weather[0].astronomy[0] as $sky
  | {
      place: (if $place != "" then $place else (.nearest_area[0].areaName[0].value // "") end),
      lat: (.nearest_area[0].latitude | tonumber),
      lon: (.nearest_area[0].longitude | tonumber),
      unit: $unit,
      temp: $now["temp_" + $unit],
      feels: $now["FeelsLike" + $unit],
      desc: ($now.weatherDesc[0].value | trim),
      code: ($now.weatherCode | tonumber),
      cloudcover: ($now.cloudcover | tonumber),
      precipMM: ($now.precipMM | tonumber),
      visibility: ($now.visibility | tonumber),
      windKmph: ($now.windspeedKmph | tonumber),
      windDegree: ($now.winddirDegree | tonumber),
      sunrise: ($sky.sunrise | minutes),
      sunset: ($sky.sunset | minutes),
      moonrise: ($sky.moonrise | minutes),
      moonset: ($sky.moonset | minutes),
      moonIllumination: ($sky.moon_illumination | tonumber),
      days: (
        if $forecast != null and ($forecast.daily.time | length) > 0 then
          [range($forecast.daily.time | length) as $i | {
            date: $forecast.daily.time[$i],
            high: ($forecast.daily.temperature_2m_max[$i] | round | tostring),
            low: ($forecast.daily.temperature_2m_min[$i] | round | tostring),
            code: ($forecast.daily.weather_code[$i] | wttrCode)
          }]
        else
          [.weather[] | {
            date,
            high: .["maxtemp" + $unit],
            low: .["mintemp" + $unit],
            code: (.hourly[4].weatherCode | tonumber)
          }]
        end
      )
    }' <<<"$wttr"
