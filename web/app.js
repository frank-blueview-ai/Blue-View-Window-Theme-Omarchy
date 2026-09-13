// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// The Blue View OS sky as a web page (port of the Omarchy plugin's Service.qml):
// one real-time timeline, real sun and moon positions and moon phase for the
// location, weather-driven clouds that travel with the real wind, and the
// optional logo, clock and 7-day forecast.

"use strict"

const sky = (() => {
  // Settings come from the page address, or from a native wrapper (the macOS app and
  // screensaver) that sets window.BVOS_QUERY before the page loads.
  const params = new URLSearchParams(window.BVOS_QUERY || location.search)
  const flag = (name, fallback) => params.has(name) ? /^(1|true|on|yes)$/i.test(params.get(name)) : fallback

  const settings = {
    location: params.get("location") || "",
    units: (params.get("units") || "auto").toUpperCase() === "F" ? "F" : (params.get("units") || "").toUpperCase() === "C" ? "C" : "auto",
    overlay: flag("overlay", false),
    constellationLines: flag("lines", false),
    showSatellites: flag("satellites", true),
    fps: Math.max(1, Math.min(60, Number(params.get("fps")) || 24)),
    cloudDetail: Math.max(0.2, Math.min(1, Number(params.get("detail")) / 100 || 0.4)),
    previewCondition: params.get("condition") || "",
    previewHour: params.has("hour") ? Number(params.get("hour")) : -1
  }

  const state = {
    weather: null,
    time: Math.random() * 600,
    layerShiftX: [0, 0, 0],
    layerShiftY: [0, 0, 0],
    highShift: [0, 0],
    sunArc: { x: 0, y: 0.7, alt: 0.5 },
    moonArc: { x: 0, y: -0.2, alt: -1 },
    moonFraction: 0.5,
    moonWaxing: true,
    conditions: { cover: 0.45, gloom: 0.05, rain: 0, snow: 0, fog: 0, storm: 0 },
    paused: false,
    startedAt: Date.now()
  }

  // The interface StarField and Satellites read from.
  const view = {
    get located() { return state.weather !== null && isFinite(state.weather.lat) && isFinite(state.weather.lon) },
    get latitude() { return view.located ? state.weather.lat : 0 },
    get longitude() { return view.located ? state.weather.lon : 0 },
    get sunAltitudeDeg() { return Math.asin(Math.max(-1, Math.min(1, state.sunArc.alt))) * 180 / Math.PI },
    get moonAltitudeDeg() { return Math.asin(Math.max(-1, Math.min(1, state.moonArc.alt))) * 180 / Math.PI },
    get limitingMagnitude() { return Astro.limitingMagnitude(view.sunAltitudeDeg, view.moonAltitudeDeg, state.moonFraction, state.conditions.gloom) },
    get constellationLines() { return settings.constellationLines },
    get showSatellites() { return settings.showSatellites },
    skyDate
  }

  // The moment the sky shows: now, or today at the preview hour.
  function skyDate() {
    const d = new Date()
    if (settings.previewHour >= 0) {
      d.setHours(0, 0, 0, 0)
      d.setTime(d.getTime() + settings.previewHour * 3600000)
    }
    return d
  }

  // Position of a body that rises at `rise` and sets at `set` (minutes after
  // midnight), for when there's no location yet.
  function bodyArc(rise, set, now) {
    let span = set - rise
    if (span <= 0) span += 1440
    let t = now - rise
    if (t < 0) t += 1440
    if (t <= span) {
      const f = t / span
      const up = Math.sin(Math.PI * f)
      return { x: 0.08 + 0.84 * f, y: 0.30 + 0.46 * up, alt: up }
    }
    const below = (t - span) / Math.max(1, 1440 - span)
    const down = Math.sin(Math.PI * below)
    return { x: below < 0.5 ? 0.92 + below * 0.4 : 0.08 - (1 - below) * 0.4, y: 0.30 - 0.25 * down, alt: -down }
  }

  // Real sun and moon positions and phase for the location.
  function updateSky() {
    const date = skyDate()
    if (view.located) {
      state.sunArc = Astro.project(Astro.sunPosition(date, view.latitude, view.longitude), view.latitude)
      state.moonArc = Astro.project(Astro.moonPosition(date, view.latitude, view.longitude), view.latitude)
    } else {
      const minutes = date.getHours() * 60 + date.getMinutes()
      const sun = bodyArc(390, 1140, minutes)
      const moon = bodyArc(1180, 350, minutes)
      state.sunArc = { x: (sun.x - 0.5) * 1.778, y: sun.y, alt: sun.alt }
      state.moonArc = { x: (moon.x - 0.5) * 1.778, y: moon.y, alt: moon.alt }
    }
    const illumination = Astro.moonIllumination(date)
    state.moonFraction = illumination.fraction
    state.moonWaxing = illumination.waxing
    stars.paint(view)
    satellites.scan(view)
  }

  function targetConditions() {
    if (settings.previewCondition) return Weather.conditionsFor(Weather.previewCode(settings.previewCondition), -1)
    const w = state.weather
    return Weather.conditionsFor(w ? w.code : 116, w ? w.cloudcover : 30)
  }

  function windKmph() {
    if (settings.previewCondition === "storm") return 45
    return state.weather && isFinite(state.weather.windKmph) ? state.weather.windKmph : 10
  }

  function windDegree() {
    return state.weather && isFinite(state.weather.windDegree) ? state.weather.windDegree : 270
  }

  // ---- Weather: refresh every 15 minutes; retry sooner after a failure.
  let weatherTimer = 0
  async function refreshWeather() {
    clearTimeout(weatherTimer)
    let delay = 15 * 60 * 1000
    try {
      state.weather = await Weather.load(settings)
      // The first forecast lands while the page fades in; show it without a glide.
      if (Date.now() - state.startedAt < 3000 || settings.previewCondition) state.conditions = targetConditions()
      updateSky()
      renderForecast()
    } catch (e) {
      console.warn("bvos: weather unavailable: " + e.message)
      delay = 2 * 60 * 1000
    }
    weatherTimer = setTimeout(refreshWeather, delay)
  }

  // ---- Layers.
  const skyPass = new SkyPass(document.getElementById("sky"), "SKY_PASS", false)
  const cloudPass = new SkyPass(document.getElementById("clouds"), "CLOUD_PASS", true)
  const stars = new StarField(document.getElementById("stars"))
  const satellites = new Satellites(document.getElementById("satellites"))

  function resize() {
    const w = window.innerWidth
    const h = window.innerHeight
    const ratio = window.devicePixelRatio || 1
    // Clouds are soft, so a low-res render upscaled looks the same and keeps
    // integrated GPUs cool. The sky gradient is smoother still.
    cloudPass.renderScale = settings.cloudDetail
    skyPass.renderScale = settings.cloudDetail * 0.5
    skyPass.resize(w, h, ratio)
    cloudPass.resize(w, h, ratio)
    stars.resize(w, h, ratio)
    satellites.resize(w, h, ratio)

    // Composition steps in powers of φ from one base unit.
    const u = h * 0.0118
    for (let n = -2; n <= 4; n++) document.documentElement.style.setProperty("--s" + n, (u * Math.pow(1.6180339887, n)).toFixed(2) + "px")
    stars.paint(view)
    satellites.track(view)
  }

  // ---- Animation.
  let lastTick = performance.now()
  let lastFrame = 0
  let lastTrack = 0

  function ease(dt) {
    const target = targetConditions()
    const k = 1 - Math.exp(-dt / 1.3)
    for (const key in target) state.conditions[key] += (target[key] - state.conditions[key]) * k
  }

  function advance(now) {
    const dt = Math.min(5, Math.max(0, (now - lastTick) / 1000))
    lastTick = now
    state.time += dt
    ease(dt)

    const v = Astro.cloudVelocities(windKmph(), windDegree(), view.latitude)
    for (let i = 0; i < 3; i++) {
      state.layerShiftX[i] += dt * v.layers[i].x
      state.layerShiftY[i] += dt * v.layers[i].y
    }
    state.highShift[0] += dt * v.high.x
    state.highShift[1] += dt * v.high.y

    // Keep shader inputs small enough for float precision.
    if (state.time > 7200) state.time -= 1800
    const travel = Math.max(Math.abs(state.layerShiftX[2]), Math.abs(state.layerShiftY[2]), Math.abs(state.highShift[0]))
    if (travel > 400) {
      state.layerShiftX = [0, 0, 0]
      state.layerShiftY = [0, 0, 0]
      state.highShift = [0, 0]
    }
  }

  function draw() {
    const c = state.conditions
    const values = {
      qt_Opacity: 1,
      time: state.time,
      sunPos: [state.sunArc.x, state.sunArc.y],
      sunAlt: state.sunArc.alt,
      moonPos: [state.moonArc.x, state.moonArc.y],
      moonAlt: state.moonArc.alt,
      moonLight: state.moonFraction,
      moonWaxing: state.moonWaxing ? 1 : -1,
      cover: c.cover,
      gloom: c.gloom,
      rain: c.rain,
      snow: c.snow,
      fog: c.fog,
      storm: c.storm,
      layerShiftX: state.layerShiftX,
      layerShiftY: state.layerShiftY,
      highShift: state.highShift
    }
    skyPass.render(values)
    cloudPass.render(values)
  }

  function frame(now) {
    requestAnimationFrame(frame)
    if (state.paused || now - lastFrame < 1000 / settings.fps - 2) return
    lastFrame = now
    advance(now)
    draw()
    if (satellites.candidates.length > 0 && now - lastTrack > 100) {
      lastTrack = now
      satellites.track(view)
    }
  }

  // ---- Logo, clock and forecast.
  const $ = id => document.getElementById(id)

  function renderClock() {
    const now = new Date()
    $("clock").textContent = (now.getHours() % 12 || 12) + ":" + String(now.getMinutes()).padStart(2, "0")
    $("date").textContent = now.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })

    // A barely-there drift keeps pixels fresh without breaking the proportions.
    const w = window.innerWidth
    const h = window.innerHeight
    const phi = 1.6180339887
    const axisX = w / phi + Math.sin(state.time * 0.013) * w * 0.008
    const driftY = Math.cos(state.time * 0.011) * h * 0.006
    $("brand").style.left = $("forecast").style.left = axisX.toFixed(1) + "px"
    $("brand").style.top = (h * (1 - 1 / phi) + driftY).toFixed(1) + "px"
    $("forecast").style.top = (h / phi + driftY).toFixed(1) + "px"
  }

  function renderForecast() {
    const w = state.weather
    $("forecast").hidden = !w
    if (!w) return
    $("now-icon").textContent = Weather.icon(w.code, state.sunArc.alt < 0)
    $("now-temp").textContent = w.temp + "°" + w.unit
    $("now-desc").textContent = w.desc
    $("now-place").textContent = w.place
    const days = $("days")
    days.textContent = ""
    w.days.forEach((d, i) => {
      const parts = d.date.split("-").map(Number)
      const name = i === 0 ? "Today" : new Date(parts[0], parts[1] - 1, parts[2]).toLocaleDateString("en-US", { weekday: "short" })
      const column = document.createElement("div")
      column.className = "day"
      for (const [cls, text] of [["name", name], ["wi", Weather.icon(d.code, false)], ["high", d.high + "°"], ["low", d.low + "°"]]) {
        const cell = document.createElement("div")
        cell.className = cls
        cell.textContent = text
        column.appendChild(cell)
      }
      days.appendChild(column)
    })
  }

  function applyOverlay() {
    $("composition").hidden = !settings.overlay
  }

  // ---- Lively Wallpaper (Windows) settings and playback.
  const UNITS = ["auto", "F", "C"]
  window.livelyPropertyListener = (name, value) => {
    switch (name) {
      case "location":
        // Lively sends the text on every key press; look it up once typing pauses.
        if (settings.location !== String(value)) {
          settings.location = String(value)
          clearTimeout(weatherTimer)
          weatherTimer = setTimeout(refreshWeather, 1500)
        }
        break
      case "units":
        if (settings.units !== UNITS[value]) { settings.units = UNITS[value] || "auto"; refreshWeather() }
        break
      case "overlay": settings.overlay = !!value; applyOverlay(); break
      case "constellations": settings.constellationLines = !!value; stars.paint(view); break
      case "satellites": settings.showSatellites = !!value; satellites.scan(view); break
      case "fps": settings.fps = Math.max(1, Math.min(60, Number(value) || 24)); break
      case "detail": settings.cloudDetail = Math.max(0.2, Math.min(1, Number(value) / 100 || 0.4)); resize(); break
    }
  }

  window.livelyWallpaperPlaybackChanged = data => {
    try { state.paused = !!JSON.parse(data).IsPaused } catch (e) {}
    lastTick = performance.now()
  }

  document.addEventListener("visibilitychange", () => { lastTick = performance.now() })

  // ---- Start.
  state.conditions = targetConditions()
  window.addEventListener("resize", resize)
  resize()
  updateSky()
  applyOverlay()
  renderClock()
  setInterval(renderClock, 1000)
  setInterval(updateSky, 5000)
  const loadSatellites = () => satellites.load().then(() => {
    satellites.scan(view)
    setTimeout(loadSatellites, satellites.records.length > 0 ? 6 * 3600 * 1000 : 10 * 60 * 1000)
  })
  loadSatellites()
  refreshWeather()
  requestAnimationFrame(frame)
  setTimeout(() => document.body.classList.remove("starting"), 60)

  return { settings, state, view, satellites }
})()
