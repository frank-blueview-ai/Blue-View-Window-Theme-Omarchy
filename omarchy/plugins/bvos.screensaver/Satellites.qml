// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.

import QtQuick
import Quickshell.Io
import "Astro.js" as Astro
import "SGP4.js" as SGP4

// Real satellites passing overhead: the International Space Station, China's
// Tiangong station, and CelesTrak's list of the brightest satellites. Orbits
// are propagated with SGP4 from current elements. As in the real sky, one is
// shown only when it's above the horizon, lit by the sun while the observer's
// sky is dark, and bright enough for the eye.
Item {
  id: sats

  required property var service

  property var records: []     // { label, name, satrec, standardMagnitude }
  property var candidates: []  // records above the horizon at the last scan
  property var shown: []       // { label, x, y, magnitude }

  readonly property bool darkEnough: service.sunAltitudeDeg < -4 && service.limitingMagnitude > 0

  // Known stations get names and realistic brightness; the rest stay anonymous.
  function describe(name, group) {
    var n = name.trim()
    if (group === "stations") {
      if (n.indexOf("ISS (ZARYA)") === 0) return { label: "ISS", standardMagnitude: -1.8 }
      if (n.indexOf("CSS (TIANHE)") === 0) return { label: "Tiangong", standardMagnitude: -0.5 }
      return null   // other modules and visiting craft share those orbits
    }
    return { label: "", standardMagnitude: 3.5 }
  }

  function parse(text) {
    var lines = String(text).split("\n")
    var group = ""
    var seen = {}
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (line.indexOf("# group ") === 0) { group = line.substring(8).trim(); continue }
      if (i + 2 >= lines.length || lines[i + 1].indexOf("1 ") !== 0 || lines[i + 2].indexOf("2 ") !== 0) continue
      var id = lines[i + 1].substring(2, 7)
      var info = describe(line, group)
      i += 2
      if (!info || seen[id]) continue
      seen[id] = true
      try {
        var satrec = SGP4.satellite.twoline2satrec(lines[i - 1], lines[i])
        out.push({ label: info.label, name: line.trim(), satrec: satrec, standardMagnitude: info.standardMagnitude })
      } catch (e) {}
    }
    sats.records = out
    sats.scan()
  }

  // Look angles and brightness for one satellite, or null if it can't be seen.
  function observe(record, date, gmst, observer, sun) {
    var pv = SGP4.satellite.propagate(record.satrec, date)
    if (!pv || !pv.position) return null
    var look = SGP4.satellite.ecfToLookAngles(observer, SGP4.satellite.eciToEcf(pv.position, gmst))
    if (look.elevation <= 0) return { above: false }
    if (!Astro.sunlit(pv.position, sun)) return { above: true, seen: false }
    var magnitude = Astro.satelliteMagnitude(record.standardMagnitude, look.rangeSat)
    if (magnitude > sats.service.limitingMagnitude + 0.5) return { above: true, seen: false }
    // ecfToLookAngles gives azimuth from north; the projection wants it from south, west positive.
    var p = Astro.project({ azimuth: look.azimuth - Math.PI, altitude: look.elevation }, sats.service.latitude)
    return { above: true, seen: true, x: sats.width / 2 + p.x * sats.height, y: sats.height - p.y * sats.height, magnitude: magnitude }
  }

  function context() {
    var date = sats.service.skyDate()
    var deg = Math.PI / 180
    return {
      date: date,
      gmst: SGP4.satellite.gstime(date),
      observer: { latitude: sats.service.latitude * deg, longitude: sats.service.longitude * deg, height: 0 },
      sun: Astro.sunDirection(date)
    }
  }

  // Every few seconds: find which satellites are above the horizon.
  function scan() {
    if (!sats.darkEnough || !sats.service.located || sats.records.length === 0) {
      sats.candidates = []
      sats.shown = []
      return
    }
    var c = sats.context()
    var above = []
    for (var i = 0; i < sats.records.length; i++) {
      var o = sats.observe(sats.records[i], c.date, c.gmst, c.observer, c.sun)
      if (o && o.above) above.push(sats.records[i])
    }
    sats.candidates = above
    sats.track()
  }

  // Many times a second: move the ones above the horizon along their orbits.
  function track() {
    if (sats.candidates.length === 0) { sats.shown = []; return }
    var c = sats.context()
    var out = []
    for (var i = 0; i < sats.candidates.length; i++) {
      var o = sats.observe(sats.candidates[i], c.date, c.gmst, c.observer, c.sun)
      if (o && o.seen && o.x > -20 && o.x < sats.width + 20)
        out.push({ label: sats.candidates[i].label, x: o.x, y: o.y, magnitude: o.magnitude })
    }
    sats.shown = out
  }

  Process {
    id: fetch
    running: true
    command: ["bash", sats.service.pluginDir + "/satellites.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: sats.parse(text)
    }
  }

  Timer {
    interval: 6 * 3600 * 1000
    repeat: true
    running: true
    onTriggered: fetch.running = true
  }

  Timer {
    interval: 4000
    repeat: true
    running: sats.visible && sats.darkEnough
    triggeredOnStart: true
    onTriggered: sats.scan()
    onRunningChanged: if (!running) { sats.candidates = []; sats.shown = [] }
  }

  Timer {
    interval: 100
    repeat: true
    running: sats.visible && sats.candidates.length > 0
    onTriggered: sats.track()
  }

  Repeater {
    model: sats.shown

    Item {
      required property var modelData
      readonly property real px: sats.height / 1080
      readonly property real brightness: Math.max(0.25, Math.min(1, (sats.service.limitingMagnitude - modelData.magnitude) / 2))
      x: modelData.x
      y: modelData.y

      Rectangle {
        readonly property real size: Math.max(1.6, 3.2 - 0.35 * modelData.magnitude) * parent.px
        x: -size / 2
        y: -size / 2
        width: size
        height: size
        radius: size / 2
        color: "#fff6e8"
        opacity: parent.brightness
      }

      Text {
        visible: modelData.label !== ""
        x: 8 * parent.px
        y: -14 * parent.px
        text: modelData.label
        color: "#dbe9ff"
        opacity: 0.55 * parent.brightness
        font.family: "Manrope"
        font.pixelSize: Math.round(11 * parent.px)
        font.letterSpacing: 1.5 * parent.px
      }
    }
  }
}
