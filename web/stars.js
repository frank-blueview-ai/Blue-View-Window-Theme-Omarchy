// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// The real night sky (port of StarField.qml): the 2,887 naked-eye stars of the
// Yale Bright Star Catalogue, precessed to today, placed by local sidereal time
// and latitude, colored by B-V index, and shown only as bright as the sky
// allows. Constellation lines are optional and appear faintly once it's dark.

"use strict"

class StarField {
  constructor(canvas) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    const now = new Date()
    // [ra, dec, magnitude, "r,g,b"], brightest first
    this.stars = BVOS_STAR_DATA.stars.map(s => {
      const eq = Astro.precess(s[0], s[1], now)
      const c = Astro.starColor(s[3])
      return [eq.ra, eq.dec, s[2], Math.round(c[0]) + "," + Math.round(c[1]) + "," + Math.round(c[2])]
    })
    // Polylines of [ra, dec]
    this.constellations = []
    for (const constellation of BVOS_STAR_DATA.constellations)
      for (const line of constellation.lines)
        this.constellations.push(line.map(pt => { const eq = Astro.precess(pt[0], pt[1], now); return [eq.ra, eq.dec] }))
  }

  resize(cssWidth, cssHeight, pixelRatio) {
    this.canvas.width = Math.round(cssWidth * pixelRatio)
    this.canvas.height = Math.round(cssHeight * pixelRatio)
  }

  paint(sky) {
    const ctx = this.ctx
    const w = this.canvas.width
    const h = this.canvas.height
    ctx.clearRect(0, 0, w, h)

    const lim = sky.limitingMagnitude
    if (!sky.located || lim < -1.5) return

    const date = sky.skyDate()
    const lst = Astro.localSiderealTime(date, sky.longitude)
    const phi = sky.latitude * Math.PI / 180
    const cx = w / 2
    const px = h / 1080

    const toScreen = (ra, dec) => {
      const hz = Astro.horizontal(ra, dec, lst, phi)
      if (hz.altitude < -0.03) return null
      const p = Astro.project(hz, sky.latitude)
      const x = cx + p.x * h
      if (x < -40 || x > w + 40) return null
      return [x, h - p.y * h]
    }

    // Constellation figures, when turned on, only under a properly dark sky.
    const lineAlpha = sky.constellationLines ? Math.max(0, Math.min(1, (lim - 3.0) / 2.0)) * 0.20 : 0
    if (lineAlpha > 0.01) {
      ctx.strokeStyle = "rgba(160, 200, 255, " + lineAlpha.toFixed(3) + ")"
      ctx.lineWidth = Math.max(1, px)
      ctx.beginPath()
      for (const line of this.constellations) {
        let prev = null
        for (const point of line) {
          const pt = toScreen(point[0], point[1])
          if (pt && prev && Math.abs(pt[0] - prev[0]) < w / 3) {
            ctx.moveTo(prev[0], prev[1])
            ctx.lineTo(pt[0], pt[1])
          }
          prev = pt
        }
      }
      ctx.stroke()
    }

    // Stars, brightest first, down to what the eye can see right now.
    for (const star of this.stars) {
      const mag = star[2]
      if (mag > lim) break
      const sp = toScreen(star[0], star[1])
      if (!sp) continue
      const alpha = Math.min(1, (lim - mag) / 1.5)
      const radius = Math.max(0.55, 2.3 - 0.38 * mag) * px
      if (mag < 1.0) {
        ctx.fillStyle = "rgba(" + star[3] + ", " + (alpha * 0.16).toFixed(3) + ")"
        ctx.beginPath()
        ctx.arc(sp[0], sp[1], radius * 3.2, 0, 2 * Math.PI)
        ctx.fill()
      }
      ctx.fillStyle = "rgba(" + star[3] + ", " + alpha.toFixed(3) + ")"
      ctx.beginPath()
      ctx.arc(sp[0], sp[1], radius, 0, 2 * Math.PI)
      ctx.fill()
    }
  }
}
