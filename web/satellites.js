// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// Real satellites passing overhead (port of Satellites.qml): the ISS, China's
// Tiangong station, and CelesTrak's brightest satellites, propagated with SGP4.
// One is shown only when it's above the horizon, sunlit while the observer's
// sky is dark, and bright enough for the eye.

"use strict"

class Satellites {
  constructor(canvas) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    this.records = []     // { label, satrec, standardMagnitude }
    this.candidates = []  // records above the horizon at the last scan
    this.shown = 0
  }

  resize(cssWidth, cssHeight, pixelRatio) {
    this.canvas.width = Math.round(cssWidth * pixelRatio)
    this.canvas.height = Math.round(cssHeight * pixelRatio)
  }

  // CelesTrak asks clients not to download the same data more than every 2 hours; cache for 12.
  async load() {
    const key = "bvos.tle"
    const maxAge = 12 * 3600 * 1000
    let cached = null
    try { cached = JSON.parse(localStorage.getItem(key)) } catch (e) {}
    if (cached && Date.now() - cached.fetchedAt < maxAge && cached.text) {
      this.parse(cached.text)
      return
    }
    try {
      let text = ""
      for (const group of ["stations", "visual"]) {
        const response = await fetch("https://celestrak.org/NORAD/elements/gp.php?GROUP=" + group + "&FORMAT=tle", { cache: "no-store" })
        const body = response.ok ? await response.text() : ""
        if (/^1 /m.test(body)) text += "# group " + group + "\n" + body.replace(/\r/g, "") + "\n"
      }
      if (!text) throw new Error("no elements")
      try { localStorage.setItem(key, JSON.stringify({ fetchedAt: Date.now(), text })) } catch (e) {}
      this.parse(text)
    } catch (e) {
      console.warn("bvos: satellite elements unavailable")
      if (cached && cached.text) this.parse(cached.text)
    }
  }

  // Known stations get names and realistic brightness; the rest stay anonymous.
  describe(name, group) {
    const n = name.trim()
    if (group === "stations") {
      if (n.indexOf("ISS (ZARYA)") === 0) return { label: "ISS", standardMagnitude: -1.8 }
      if (n.indexOf("CSS (TIANHE)") === 0) return { label: "Tiangong", standardMagnitude: -0.5 }
      return null   // other modules and visiting craft share those orbits
    }
    return { label: "", standardMagnitude: 3.5 }
  }

  parse(text) {
    const lines = String(text).split("\n")
    const seen = {}
    const out = []
    let group = ""
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (line.indexOf("# group ") === 0) { group = line.substring(8).trim(); continue }
      if (i + 2 >= lines.length || lines[i + 1].indexOf("1 ") !== 0 || lines[i + 2].indexOf("2 ") !== 0) continue
      const id = lines[i + 1].substring(2, 7)
      const info = this.describe(line, group)
      i += 2
      if (!info || seen[id]) continue
      seen[id] = true
      try {
        out.push({ label: info.label, satrec: SGP4.satellite.twoline2satrec(lines[i - 1], lines[i]), standardMagnitude: info.standardMagnitude })
      } catch (e) {}
    }
    this.records = out
  }

  darkEnough(sky) {
    return sky.sunAltitudeDeg < -4 && sky.limitingMagnitude > 0
  }

  context(sky) {
    const date = sky.skyDate()
    const deg = Math.PI / 180
    return {
      date,
      gmst: SGP4.satellite.gstime(date),
      observer: { latitude: sky.latitude * deg, longitude: sky.longitude * deg, height: 0 },
      sun: Astro.sunDirection(date)
    }
  }

  // Look angles and brightness for one satellite, or null if it can't be computed.
  observe(sky, record, c) {
    const pv = SGP4.satellite.propagate(record.satrec, c.date)
    if (!pv || !pv.position) return null
    const look = SGP4.satellite.ecfToLookAngles(c.observer, SGP4.satellite.eciToEcf(pv.position, c.gmst))
    if (look.elevation <= 0) return { above: false }
    if (!Astro.sunlit(pv.position, c.sun)) return { above: true, seen: false }
    const magnitude = Astro.satelliteMagnitude(record.standardMagnitude, look.rangeSat)
    if (magnitude > sky.limitingMagnitude + 0.5) return { above: true, seen: false }
    // ecfToLookAngles gives azimuth from north; the projection wants it from south, west positive.
    const p = Astro.project({ azimuth: look.azimuth - Math.PI, altitude: look.elevation }, sky.latitude)
    const h = this.canvas.height
    return { above: true, seen: true, x: this.canvas.width / 2 + p.x * h, y: h - p.y * h, magnitude }
  }

  // Every few seconds: find which satellites are above the horizon.
  scan(sky) {
    this.candidates = []
    if (sky.showSatellites && sky.located && this.darkEnough(sky)) {
      const c = this.context(sky)
      for (const record of this.records) {
        const o = this.observe(sky, record, c)
        if (o && o.above) this.candidates.push(record)
      }
    }
    this.track(sky)
  }

  // Many times a second: move the ones above the horizon along their orbits.
  track(sky) {
    const ctx = this.ctx
    const w = this.canvas.width
    const h = this.canvas.height
    if (this.shown > 0 || this.candidates.length > 0) ctx.clearRect(0, 0, w, h)
    this.shown = 0
    if (this.candidates.length === 0) return

    const c = this.context(sky)
    const px = h / 1080
    for (const record of this.candidates) {
      const o = this.observe(sky, record, c)
      if (!o || !o.seen || o.x < -20 || o.x > w + 20) continue
      this.shown++
      const brightness = Math.max(0.25, Math.min(1, (sky.limitingMagnitude - o.magnitude) / 2))
      const size = Math.max(1.6, 3.2 - 0.35 * o.magnitude) * px
      ctx.globalAlpha = brightness
      ctx.fillStyle = "#fff6e8"
      ctx.beginPath()
      ctx.arc(o.x, o.y, size / 2, 0, 2 * Math.PI)
      ctx.fill()
      if (record.label) {
        ctx.globalAlpha = 0.55 * brightness
        ctx.fillStyle = "#dbe9ff"
        ctx.font = Math.round(11 * px) + "px Manrope, sans-serif"
        ctx.letterSpacing = (1.5 * px) + "px"
        ctx.textBaseline = "top"
        ctx.fillText(record.label, o.x + 8 * px, o.y - 14 * px)
      }
    }
    ctx.globalAlpha = 1
  }
}
