// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.

import QtQuick
import Quickshell.Io
import "Astro.js" as Astro

// The real night sky: the 2,887 naked-eye stars of the Yale Bright Star
// Catalogue (to magnitude 5.5), precessed to today, placed by local sidereal
// time and latitude, colored by B-V index, and shown only as bright as the sky
// allows: stars come out in order of brightness as twilight deepens, and
// moonlight, overcast and daylight hide them. Constellation lines are
// optional (off by default) and appear faintly once the sky is dark.
// Drawn sharp at full resolution.
Canvas {
  id: field

  required property var service

  property var stars: []           // [ra, dec, magnitude, "r,g,b"], brightest first
  property var constellations: []  // polylines of [ra, dec]

  renderTarget: Canvas.FramebufferObject
  renderStrategy: Canvas.Cooperative

  function loadStars(text) {
    var now = new Date()
    var parsed = JSON.parse(text).stars
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      var s = parsed[i]
      var eq = Astro.precess(s[0], s[1], now)
      var c = Astro.starColor(s[3])
      out.push([eq.ra, eq.dec, s[2], Math.round(c[0]) + "," + Math.round(c[1]) + "," + Math.round(c[2])])
    }
    field.stars = out
    field.requestPaint()
  }

  function loadConstellations(text) {
    var now = new Date()
    var parsed = JSON.parse(text).constellations
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      for (var j = 0; j < parsed[i].lines.length; j++) {
        out.push(parsed[i].lines[j].map(function(pt) {
          var eq = Astro.precess(pt[0], pt[1], now)
          return [eq.ra, eq.dec]
        }))
      }
    }
    field.constellations = out
    field.requestPaint()
  }

  FileView {
    path: field.service.pluginDir + "/stars.json"
    onLoaded: field.loadStars(text())
  }

  FileView {
    path: field.service.pluginDir + "/constellations.json"
    onLoaded: field.loadConstellations(text())
  }

  Connections {
    target: field.service
    function onSkyRevisionChanged() { field.requestPaint() }
  }

  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()

    var sky = field.service
    var lim = sky.limitingMagnitude
    if (!sky.located || lim < -1.5 || field.stars.length === 0) return

    var date = sky.skyDate()
    var lst = Astro.localSiderealTime(date, sky.longitude)
    var phi = sky.latitude * Math.PI / 180
    var h = field.height
    var cx = field.width / 2
    var px = h / 1080

    function toScreen(ra, dec) {
      var hz = Astro.horizontal(ra, dec, lst, phi)
      if (hz.altitude < -0.03) return null
      var p = Astro.project(hz, sky.latitude)
      var x = cx + p.x * h
      if (x < -40 || x > field.width + 40) return null
      return [x, h - p.y * h]
    }

    // Constellation figures, when turned on, only under a properly dark sky.
    var lineAlpha = sky.constellationLines ? Math.max(0, Math.min(1, (lim - 3.0) / 2.0)) * 0.20 : 0
    if (lineAlpha > 0.01) {
      ctx.strokeStyle = "rgba(160, 200, 255, " + lineAlpha.toFixed(3) + ")"
      ctx.lineWidth = Math.max(1, px)
      ctx.beginPath()
      for (var i = 0; i < field.constellations.length; i++) {
        var line = field.constellations[i]
        var prev = null
        for (var j = 0; j < line.length; j++) {
          var pt = toScreen(line[j][0], line[j][1])
          if (pt && prev && Math.abs(pt[0] - prev[0]) < field.width / 3) {
            ctx.moveTo(prev[0], prev[1])
            ctx.lineTo(pt[0], pt[1])
          }
          prev = pt
        }
      }
      ctx.stroke()
    }

    // Stars, brightest first, down to what the eye can see right now.
    for (var k = 0; k < field.stars.length; k++) {
      var star = field.stars[k]
      var mag = star[2]
      if (mag > lim) break
      var sp = toScreen(star[0], star[1])
      if (!sp) continue
      var alpha = Math.min(1, (lim - mag) / 1.5)
      var radius = Math.max(0.55, 2.3 - 0.38 * mag) * px
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
