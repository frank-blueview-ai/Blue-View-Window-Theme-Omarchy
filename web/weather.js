// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// Current weather and the 7-day forecast from Open-Meteo, for a place the user
// names or, by default, the approximate location of this computer's internet
// connection (GeoJS). Produces the same shape as the Omarchy plugin's weather.sh,
// with WMO weather codes mapped to wttr.in codes so the sky mapping is shared.

"use strict"

const Weather = (() => {
  // WMO weather code -> the equivalent wttr.in code (same table as weather.sh).
  const WTTR_CODE = {
    0: 113, 1: 116, 2: 116, 3: 122, 45: 248, 48: 260,
    51: 266, 53: 266, 55: 266, 56: 281, 57: 284,
    61: 296, 63: 302, 65: 308, 66: 311, 67: 314,
    71: 326, 73: 332, 75: 338, 77: 179,
    80: 353, 81: 356, 82: 359, 85: 368, 86: 371,
    95: 389, 96: 395, 99: 395
  }

  const DESCRIPTION = {
    0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast", 45: "Fog", 48: "Freezing fog",
    51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
    71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
    80: "Rain showers", 81: "Rain showers", 82: "Heavy showers", 85: "Snow showers", 86: "Snow showers",
    95: "Thunderstorm", 96: "Thunderstorm, hail", 99: "Thunderstorm, hail"
  }

  // Countries that use Fahrenheit day to day.
  const FAHRENHEIT = ["US", "LR", "MM", "BS", "BZ", "KY", "PW", "FM", "MH"]

  async function getJSON(url, timeoutMs) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs || 10000)
    try {
      const response = await fetch(url, { signal: controller.signal, cache: "no-store" })
      if (!response.ok) throw new Error(url + ": HTTP " + response.status)
      return await response.json()
    } finally {
      clearTimeout(timer)
    }
  }

  // { name, lat, lon, country }
  async function locate(query) {
    if (query && query.trim()) {
      // Geocoding matches the city alone, so "Lynn, MA" searches "Lynn" and prefers the hint.
      const parts = query.split(",").map(s => s.trim()).filter(Boolean)
      const url = "https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&format=json&name=" + encodeURIComponent(parts[0])
      const results = (await getJSON(url)).results || []
      if (results.length === 0) throw new Error("Place not found: " + query)
      const hint = parts.slice(1).join(" ").toLowerCase()
      const match = (hint && results.find(r => [r.admin1, r.country, r.country_code].some(v => v && (v.toLowerCase() === hint || v.toLowerCase().startsWith(hint))))) ||
        (hint && results.find(r => /^[a-z]{2}$/.test(hint) && r.country_code === "US" && US_STATES[hint.toUpperCase()] === r.admin1)) ||
        results[0]
      return { name: match.name, lat: match.latitude, lon: match.longitude, country: match.country_code }
    }
    const geo = await getJSON("https://get.geojs.io/v1/ip/geo.json")
    return { name: geo.city || geo.region || "", lat: Number(geo.latitude), lon: Number(geo.longitude), country: geo.country_code }
  }

  const US_STATES = {
    AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California", CO: "Colorado", CT: "Connecticut",
    DE: "Delaware", FL: "Florida", GA: "Georgia", HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa",
    KS: "Kansas", KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland", MA: "Massachusetts", MI: "Michigan",
    MN: "Minnesota", MS: "Mississippi", MO: "Missouri", MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire",
    NJ: "New Jersey", NM: "New Mexico", NY: "New York", NC: "North Carolina", ND: "North Dakota", OH: "Ohio",
    OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina", SD: "South Dakota",
    TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont", VA: "Virginia", WA: "Washington", WV: "West Virginia",
    WI: "Wisconsin", WY: "Wyoming", DC: "District of Columbia"
  }

  // settings: { location: string, units: "auto" | "F" | "C" }
  async function load(settings) {
    const place = await locate(settings.location)
    const unit = settings.units === "F" || settings.units === "C" ? settings.units
      : FAHRENHEIT.indexOf(place.country) !== -1 ? "F" : "C"
    const url = "https://api.open-meteo.com/v1/forecast?latitude=" + place.lat + "&longitude=" + place.lon +
      "&current=temperature_2m,apparent_temperature,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m" +
      "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
      "&temperature_unit=" + (unit === "F" ? "fahrenheit" : "celsius") +
      "&wind_speed_unit=kmh&timezone=auto&forecast_days=7"
    const data = await getJSON(url)
    const now = data.current
    const wmo = Number(now.weather_code)
    return {
      place: place.name,
      lat: place.lat,
      lon: place.lon,
      unit: unit,
      temp: String(Math.round(now.temperature_2m)),
      feels: String(Math.round(now.apparent_temperature)),
      desc: DESCRIPTION[wmo] || "",
      code: WTTR_CODE[wmo] || 119,
      cloudcover: Number(now.cloud_cover),
      windKmph: Number(now.wind_speed_10m),
      windDegree: Number(now.wind_direction_10m),
      days: data.daily.time.map((date, i) => ({
        date: date,
        high: String(Math.round(data.daily.temperature_2m_max[i])),
        low: String(Math.round(data.daily.temperature_2m_min[i])),
        code: WTTR_CODE[data.daily.weather_code[i]] || 119
      }))
    }
  }

  // Map a wttr.in weather code (and cloud cover %) to how the sky should look (as in Service.qml).
  function conditionsFor(code, cloudcover) {
    const c = Number(code)
    const has = list => list.indexOf(c) !== -1
    let k = { cover: 0.12, gloom: 0, rain: 0, snow: 0, fog: 0, storm: 0 }

    if (c === 116) k = { cover: 0.45, gloom: 0.05, rain: 0, snow: 0, fog: 0, storm: 0 }
    else if (c === 119) k = { cover: 0.75, gloom: 0.25, rain: 0, snow: 0, fog: 0, storm: 0 }
    else if (c === 122) k = { cover: 1.0, gloom: 0.45, rain: 0, snow: 0, fog: 0, storm: 0 }
    else if (c === 143) k = { cover: 0.6, gloom: 0.2, rain: 0, snow: 0, fog: 0.45, storm: 0 }
    else if (has([248, 260])) k = { cover: 0.7, gloom: 0.3, rain: 0, snow: 0, fog: 0.8, storm: 0 }
    else if (has([200, 386, 389, 392, 395])) k = { cover: 1.0, gloom: 0.8, rain: 0.8, snow: has([392, 395]) ? 0.5 : 0, fog: 0.1, storm: 1.0 }
    else if (has([305, 308, 356, 359])) k = { cover: 1.0, gloom: 0.7, rain: 1.0, snow: 0, fog: 0.15, storm: 0 }
    else if (has([299, 302])) k = { cover: 1.0, gloom: 0.6, rain: 0.7, snow: 0, fog: 0.1, storm: 0 }
    else if (has([176, 263, 266, 293, 296, 353])) k = { cover: 0.9, gloom: 0.45, rain: 0.4, snow: 0, fog: 0.05, storm: 0 }
    else if (has([182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377])) k = { cover: 1.0, gloom: 0.55, rain: 0.5, snow: 0.4, fog: 0.1, storm: 0 }
    else if (has([227, 230])) k = { cover: 1.0, gloom: 0.55, rain: 0, snow: 1.0, fog: 0.45, storm: 0 }
    else if (has([329, 332, 335, 338, 371])) k = { cover: 1.0, gloom: 0.5, rain: 0, snow: 0.85, fog: 0.15, storm: 0 }
    else if (has([179, 323, 326, 368])) k = { cover: 0.9, gloom: 0.4, rain: 0, snow: 0.45, fog: 0.05, storm: 0 }

    if (cloudcover >= 0) k.cover = Math.max(k.cover, Math.min(1, cloudcover / 100) * 0.9)
    return k
  }

  function previewCode(name) {
    return ({ clear: 113, partly: 116, cloudy: 119, overcast: 122, rain: 302, storm: 389, snow: 332, fog: 248 })[name] || 116
  }

  // Weather Icons glyphs (day, night): the same icons Omarchy's weather widget
  // picks from its Nerd Font, at their codepoints in the Weather Icons font.
  function icon(code, night) {
    const c = Number(code)
    const pick = (day, dark) => String.fromCharCode(night ? dark : day)
    if (c === 113) return pick(0xf00d, 0xf02e)                                   // sunny / clear night
    if (c === 116) return pick(0xf002, 0xf031)                                   // partly cloudy
    if ([119, 122].indexOf(c) !== -1) return pick(0xf041, 0xf041)                // cloud
    if ([143, 248, 260].indexOf(c) !== -1) return pick(0xf014, 0xf014)           // fog
    if ([176, 263, 353].indexOf(c) !== -1) return pick(0xf008, 0xf036)           // showers
    if ([179, 227, 230, 323, 326, 368].indexOf(c) !== -1) return pick(0xf00a, 0xf02a)   // light snow
    if ([182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377].indexOf(c) !== -1) return pick(0xf0b5, 0xf0b5)   // sleet
    if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return pick(0xf01e, 0xf01e) // thunderstorm
    if ([266, 293, 296, 299, 302, 305, 308, 356, 359].indexOf(c) !== -1) return pick(0xf019, 0xf019)   // rain
    if ([329, 332, 335, 338, 371].indexOf(c) !== -1) return pick(0xf01b, 0xf01b) // snow
    return pick(0xf041, 0xf041)
  }

  return { load, conditionsFor, previewCode, icon }
})()
