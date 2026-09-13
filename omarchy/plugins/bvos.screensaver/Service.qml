// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Astro.js" as Astro

// Blue View OS screensaver: an animated sea of clouds with the Blue View OS
// wordmark and clock. Starts after `idle.screensaver` seconds (shell.json),
// honors stay-awake and idle inhibitors, and closes on any key or mouse input.
// Omarchy's terminal screensaver is switched off (screensaver-off toggle);
// Omarchy's idle service still locks at `idle.lock`.
//
// The sky follows the real day and the weather outside: the logo's yellow
// oval is the sun, its blue oval the moon, and the clouds match conditions.
//
// The same live sky is the desktop background, so the desktop is dark when
// it's dark outside and clouds drift behind your windows. Toggle it with:
//   omarchy-shell bvos-screensaver desktop <on|off>
// Constellation lines (off by default, for a real-looking sky):
//   omarchy-shell bvos-screensaver lines <on|off>
//
// Try it: omarchy-shell bvos-screensaver show
// Preview: omarchy-shell bvos-screensaver <preview|demo>  <clear|partly|cloudy|overcast|rain|storm|snow|fog|live> <hour 0-23|now>
Item {
  id: root

  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/bvos.screensaver"

  // Fraction of screen resolution the cloud shader renders at. Clouds are soft,
  // so a low-res render upscaled looks the same and keeps integrated GPUs cool.
  readonly property real renderScale: stillMode ? 1.0 : 0.4
  readonly property int framesPerSecond: 30

  property int timeoutSeconds: 150

  // ---- Live desktop.
  readonly property string desktopOffFlag: home + "/.local/state/bvos/live-desktop-off"
  property bool desktopEnabled: false
  readonly property int desktopFramesPerSecond: 12

  // ---- One real-time timeline for the sky, shared by desktop and screensaver.
  property real time: Math.random() * 600
  property real lastTick: Date.now()

  // ---- Real physics. See Astro.js for the viewpoint and formulas.
  readonly property bool located: weather !== null && weather.lat !== undefined && weather.lon !== undefined
  readonly property real latitude: located ? weather.lat : 0
  readonly property real longitude: located ? weather.lon : 0
  readonly property real windKmph: previewCondition === "storm" ? 45 : (weather && weather.windKmph !== undefined ? weather.windKmph : 10)
  readonly property real windDegree: weather && weather.windDegree !== undefined ? weather.windDegree : 270
  // Cloud travel from the real wind at cloud height, seen from 1 km above the cloud tops.
  readonly property var cloudVelocity: Astro.cloudVelocities(windKmph, windDegree, latitude)
  property vector3d layerShiftX: Qt.vector3d(0, 0, 0)
  property vector3d layerShiftY: Qt.vector3d(0, 0, 0)
  property vector2d highShift: Qt.vector2d(0, 0)
  property int skyRevision: 0
  // Constellation figures are a chart convention, not part of the real sky: off unless asked for.
  property bool constellationLines: false
  property real moonFraction: 0.5
  property bool moonWaxing: true
  readonly property real sunAltitudeDeg: Math.asin(Math.max(-1, Math.min(1, sunArc.alt))) * 180 / Math.PI
  readonly property real moonAltitudeDeg: Math.asin(Math.max(-1, Math.min(1, moonArc.alt))) * 180 / Math.PI
  // Faintest star the eye could see right now, given twilight, moonlight and weather.
  readonly property real limitingMagnitude: Astro.limitingMagnitude(sunAltitudeDeg, moonAltitudeDeg, moonFraction, skyGloom)
  readonly property bool desktopUncovered: desktopEnabled && Hyprland.monitors.values.some(function(m) {
    return !m.activeWorkspace || m.activeWorkspace.toplevels.values.length === 0
  })
  property bool active: false
  property bool closing: false
  // Still mode renders the bare sky at full resolution (for wallpapers) and
  // ignores input until hidden over IPC.
  property bool stillMode: false
  // Demo mode shows everything but ignores input until hidden over IPC.
  property bool demoMode: false
  property real startedAt: 0
  property var weather: null

  // ---- Sky state: time of day and weather, eased so changes glide.
  property string previewCondition: ""
  property real previewHour: -1
  property real clockMinutes: minutesNow()
  readonly property real nowMinutes: previewHour >= 0 ? previewHour * 60 : clockMinutes

  property var sunArc: ({ x: 0, y: 0.7, alt: 0.5 })
  property var moonArc: ({ x: 0, y: -0.2, alt: -1 })

  // The moment the sky shows: now, or today at the preview hour.
  function skyDate() {
    var d = new Date()
    if (root.previewHour >= 0) {
      d.setHours(0, 0, 0, 0)
      d.setTime(d.getTime() + root.previewHour * 3600000)
    }
    return d
  }

  // Real sun and moon positions, phase and sidereal rotation for the location.
  function updateSky() {
    var date = root.skyDate()
    if (root.located) {
      root.sunArc = Astro.project(Astro.sunPosition(date, root.latitude, root.longitude), root.latitude)
      root.moonArc = Astro.project(Astro.moonPosition(date, root.latitude, root.longitude), root.latitude)
    } else {
      // No location yet: approximate with typical rise and set times.
      var minutes = date.getHours() * 60 + date.getMinutes()
      var sun = bodyArc(390, 1140, minutes)
      var moon = bodyArc(1180, 350, minutes)
      root.sunArc = { x: (sun.x - 0.5) * 1.778, y: sun.y, alt: sun.alt }
      root.moonArc = { x: (moon.x - 0.5) * 1.778, y: moon.y, alt: moon.alt }
    }
    var illumination = Astro.moonIllumination(date)
    root.moonFraction = illumination.fraction
    root.moonWaxing = illumination.waxing
    root.skyRevision++
  }

  onWeatherChanged: updateSky()
  onPreviewHourChanged: updateSky()
  readonly property var conditions: conditionsFor(previewCondition !== "" ? previewCode(previewCondition) : (weather ? weather.code : 116),
                                                  previewCondition !== "" ? -1 : (weather ? weather.cloudcover : 30))

  property real skyCover: conditions.cover
  property real skyGloom: conditions.gloom
  property real skyRain: conditions.rain
  property real skySnow: conditions.snow
  property real skyFog: conditions.fog
  property real skyStorm: conditions.storm
  Behavior on skyCover { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
  Behavior on skyGloom { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
  Behavior on skyRain { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
  Behavior on skySnow { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
  Behavior on skyFog { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }
  Behavior on skyStorm { enabled: !root.stillMode; NumberAnimation { duration: 4000; easing.type: Easing.InOutSine } }

  function minutesNow() {
    var d = new Date()
    return d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60
  }

  // Position of a body that rises at `rise` and sets at `set` (minutes after
  // midnight): an arc across the sky while up, dipping below the cloud line after.
  function bodyArc(rise, set, now) {
    var span = set - rise
    if (span <= 0) span += 1440
    var t = now - rise
    if (t < 0) t += 1440
    if (t <= span) {
      var f = t / span
      var up = Math.sin(Math.PI * f)
      return { x: 0.08 + 0.84 * f, y: 0.30 + 0.46 * up, alt: up }
    }
    var below = (t - span) / Math.max(1, 1440 - span)
    var down = Math.sin(Math.PI * below)
    return { x: below < 0.5 ? 0.92 + below * 0.4 : 0.08 - (1 - below) * 0.4, y: 0.30 - 0.25 * down, alt: -down }
  }

  function previewCode(name) {
    return ({ clear: 113, partly: 116, cloudy: 119, overcast: 122, rain: 302, storm: 389, snow: 332, fog: 248 })[name] || 116
  }

  // Map a wttr.in weather code (and cloud cover %) to how the sky should look.
  function conditionsFor(code, cloudcover) {
    var c = Number(code)
    function has(list) { return list.indexOf(c) !== -1 }
    var k = { cover: 0.12, gloom: 0, rain: 0, snow: 0, fog: 0, storm: 0 }

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
  property real weatherFetchedAt: 0

  // Nerd Font weather glyphs, matching omarchy-weather-icon (day, night).
  function weatherIcon(code, night) {
    var c = Number(code)
    function pick(day, dark) { return String.fromCharCode(night ? dark : day) }
    if (c === 113) return pick(0xe30d, 0xe32b)
    if (c === 116) return pick(0xe302, 0xe32e)
    if ([119, 122].indexOf(c) !== -1) return pick(0xe33d, 0xe33d)
    if ([143, 248, 260].indexOf(c) !== -1) return pick(0xe313, 0xe313)
    if ([176, 263, 353].indexOf(c) !== -1) return pick(0xe308, 0xe333)
    if ([179, 227, 230, 323, 326, 368].indexOf(c) !== -1) return pick(0xe30a, 0xe327)
    if ([182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377].indexOf(c) !== -1) return pick(0xe3ad, 0xe3ad)
    if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return pick(0xe31d, 0xe31d)
    if ([266, 293, 296, 299, 302, 305, 308, 356, 359].indexOf(c) !== -1) return pick(0xe318, 0xe318)
    if ([329, 332, 335, 338, 371].indexOf(c) !== -1) return pick(0xe31a, 0xe31a)
    return pick(0xe33d, 0xe33d)
  }

  function dayName(isoDate, index) {
    if (index === 0) return "Today"
    var parts = String(isoDate).split("-")
    return Qt.formatDate(new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])), "ddd")
  }

  function refreshWeather() {
    // wttr.in updates about every 15 minutes; don't hammer it.
    if (weatherProc.running || Date.now() - root.weatherFetchedAt < 15 * 60 * 1000) return
    weatherProc.running = true
  }

  function readConfig(text) {
    try {
      var idle = JSON.parse(text).idle
      var seconds = idle ? Number(idle.screensaver) : NaN
      if (seconds > 0) root.timeoutSeconds = Math.round(seconds)
    } catch (e) {
      console.warn("bvos.screensaver: could not read shell.json: " + e)
    }
  }

  function start() {
    if (root.active) return
    root.closing = false
    root.startedAt = Date.now()
    root.clockMinutes = root.minutesNow()
    root.active = true
    root.refreshWeather()
    root.setCursorHidden(true)
  }

  function setCursorHidden(hidden) {
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ cursor = { invisible = " + hidden + " } })"])
  }

  function dismiss(reason) {
    if (!root.active || root.closing) return
    if ((root.stillMode || root.demoMode) && reason !== "ipc") return
    console.log("bvos.screensaver dismiss: " + reason)
    // Showing a fullscreen surface can itself look like activity; ignore it,
    // but check again once the grace period ends so real activity still wakes.
    if (Date.now() - root.startedAt < 1200) { graceTimer.restart(); return }
    root.closing = true
    root.stillMode = false
    root.demoMode = false
    closeTimer.restart()
    root.setCursorHidden(false)
  }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.readConfig(text())
    onFileChanged: reload()
  }

  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: root.timeoutSeconds
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle) gate.running = true
      else root.dismiss("activity")
    }
  }

  // Don't start over the lock screen or while stay-awake is on.
  Process {
    id: gate
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && exit 1; [[ $(omarchy-shell lock isLocked 2>/dev/null) == true ]] && exit 1; exit 0"]
    onExited: function(exitCode) { if (exitCode === 0 && idleMonitor.isIdle) root.start() }
  }

  Process {
    id: weatherProc
    command: ["bash", root.pluginDir + "/weather.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && parsed.days) {
            root.weather = parsed
            root.weatherFetchedAt = Date.now()
          }
        } catch (e) {
          console.warn("bvos.screensaver: weather unavailable")
        }
      }
    }
  }

  // Fetch once at startup so the forecast is ready the first time; refresh while showing.
  // Also bring the pointer back in case the shell restarted mid-screensaver.
  Component.onCompleted: { weatherProc.running = true; root.setCursorHidden(false) }
  Component.onDestruction: root.setCursorHidden(false)

  Timer {
    running: root.active || root.desktopEnabled
    repeat: true
    interval: 5 * 60 * 1000
    onTriggered: root.refreshWeather()
  }

  Timer {
    running: root.active || root.desktopEnabled
    repeat: true
    interval: 5000
    triggeredOnStart: true
    onTriggered: { root.clockMinutes = root.minutesNow(); root.updateSky() }
  }

  Timer {
    id: graceTimer
    interval: 1300
    onTriggered: if (root.active && !idleMonitor.isIdle) root.dismiss("activity")
  }

  Timer {
    id: closeTimer
    interval: 450
    onTriggered: { root.active = false; root.closing = false }
  }

  // Advances the sky in real time: smooth frames while it's on screen, and an
  // occasional real-time step while windows cover the desktop.
  Timer {
    running: root.active || root.desktopEnabled
    repeat: true
    interval: root.active ? Math.round(1000 / root.framesPerSecond)
      : root.desktopUncovered ? Math.round(1000 / root.desktopFramesPerSecond) : 2000
    onTriggered: {
      var now = Date.now()
      var dt = Math.min(5, Math.max(0, (now - root.lastTick) / 1000))
      root.lastTick = now
      root.time += dt
      var v = root.cloudVelocity
      root.layerShiftX = Qt.vector3d(root.layerShiftX.x + dt * v.layers[0].x, root.layerShiftX.y + dt * v.layers[1].x, root.layerShiftX.z + dt * v.layers[2].x)
      root.layerShiftY = Qt.vector3d(root.layerShiftY.x + dt * v.layers[0].y, root.layerShiftY.y + dt * v.layers[1].y, root.layerShiftY.z + dt * v.layers[2].y)
      root.highShift = Qt.vector2d(root.highShift.x + dt * v.high.x, root.highShift.y + dt * v.high.y)

      // Keep shader inputs small enough for float precision; rebase only while hidden.
      var hidden = !root.active && !root.desktopUncovered
      if ((hidden && root.time > 2400) || root.time > 7200) root.time -= 1800
      var travel = Math.max(Math.abs(root.layerShiftX.z), Math.abs(root.layerShiftY.z), Math.abs(root.highShift.x))
      if ((hidden && travel > 40) || travel > 400) {
        root.layerShiftX = Qt.vector3d(0, 0, 0)
        root.layerShiftY = Qt.vector3d(0, 0, 0)
        root.highShift = Qt.vector2d(0, 0)
      }
    }
  }

  Process {
    id: desktopFlagProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/bvos/live-desktop-off ]] && echo off || echo on"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.desktopEnabled = String(text).trim() === "on"
    }
  }

  Process {
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/bvos/constellation-lines ]] && echo on || echo off"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.constellationLines = String(text).trim() === "on"
    }
  }

  function setConstellationLines(enabled) {
    root.constellationLines = enabled
    root.skyRevision++
    Quickshell.execDetached(["bash", "-c", enabled
      ? "mkdir -p \"$HOME/.local/state/bvos\" && touch \"$HOME/.local/state/bvos/constellation-lines\""
      : "rm -f \"$HOME/.local/state/bvos/constellation-lines\""])
  }

  function setDesktop(enabled) {
    root.desktopEnabled = enabled
    Quickshell.execDetached(["bash", "-c", enabled
      ? "rm -f \"$HOME/.local/state/bvos/live-desktop-off\""
      : "mkdir -p \"$HOME/.local/state/bvos\" && touch \"$HOME/.local/state/bvos/live-desktop-off\""])
  }

  IpcHandler {
    target: "bvos-screensaver"
    function lines(state: string): string {
      if (state === "on" || state === "off") root.setConstellationLines(state === "on")
      return root.constellationLines ? "on" : "off"
    }
    function desktop(state: string): string {
      if (state === "on" || state === "off") root.setDesktop(state === "on")
      return root.desktopEnabled ? "on" : "off"
    }
    function show(): string { root.start(); return "ok" }
    function hide(): string { root.startedAt = 0; root.dismiss("ipc"); return "ok" }
    function state(): string { return root.active ? "active" : "inactive" }
    function preview(condition: string, hour: string): string {
      root.previewCondition = condition === "live" ? "" : condition
      root.previewHour = hour === "now" || hour === "" ? -1 : Number(hour)
      root.start()
      return "ok"
    }
    function weather(): string { return JSON.stringify(root.weather) }
    function sky(): string {
      return JSON.stringify({ date: root.skyDate().toString(), located: root.located, sun: root.sunArc, moon: root.moonArc,
        moonFraction: root.moonFraction, moonWaxing: root.moonWaxing, limitingMagnitude: root.limitingMagnitude, cloudVelocity: root.cloudVelocity })
    }
    function demo(condition: string, hour: string): string {
      root.demoMode = true
      return preview(condition, hour)
    }
    function still(condition: string, hour: string): string {
      root.stillMode = true
      return preview(condition, hour)
    }
  }

  Variants {
    model: root.active ? Quickshell.screens : []

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "black"

      WlrLayershell.namespace: "bvos-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      Item {
        id: scene
        anchors.fill: parent
        focus: true
        property bool shown: false
        opacity: (shown || root.stillMode) && !root.closing ? 1 : 0
        Behavior on opacity { enabled: !root.stillMode; NumberAnimation { duration: root.closing ? 400 : 2200; easing.type: Easing.InOutQuad } }
        Component.onCompleted: shown = true

        Keys.onPressed: function(event) { root.dismiss("key"); event.accepted = true }

        Sky {
          anchors.fill: parent
          service: root
          time: root.time
          renderScale: root.renderScale
        }

        // Composition on the golden ratio: everything shares one axis at 1/φ
        // across the screen; the wordmark and clock center on the upper golden
        // line (1 - 1/φ down) and the forecast sits on the lower one (1/φ down).
        // Type sizes and spacing step by powers of φ from one base unit.
        Item {
          id: composition
          anchors.fill: parent
          visible: !root.stillMode

          readonly property real phi: 1.6180339887
          readonly property real u: win.height * 0.0118
          function step(n) { return u * Math.pow(phi, n) }

          // A barely-there drift keeps pixels fresh without breaking the proportions.
          readonly property real axisX: width / phi + Math.sin(root.time * 0.013) * width * 0.008
          readonly property real driftY: Math.cos(root.time * 0.011) * height * 0.006

          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000a1e"
            shadowOpacity: 0.32
            shadowBlur: 0.9
            shadowVerticalOffset: 2
          }

          Column {
            id: brand
            x: composition.axisX - width / 2
            y: composition.height * (1 - 1 / composition.phi) - height / 2 + composition.driftY
            spacing: 0

            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              source: Qt.resolvedUrl("blueview-logo.svg")
              height: Math.round(composition.step(3))
              width: Math.round(height * 343 / 151)
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              smooth: true
            }

            Item { width: 1; height: composition.step(1) }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "BLUE VIEW OS"
              color: "#f5faff"
              opacity: 0.88
              font.family: "Manrope"
              font.weight: Font.DemiBold
              font.pixelSize: Math.round(composition.step(0))
              font.letterSpacing: Math.round(composition.step(0)) * 0.618
            }

            Item { width: 1; height: composition.step(2) }

            Text {
              id: clock
              anchors.horizontalCenter: parent.horizontalCenter
              color: "#ffffff"
              font.family: "Geist"
              font.weight: Font.ExtraLight
              font.pixelSize: Math.round(composition.step(4))
              font.letterSpacing: -Math.round(composition.step(4)) * 0.02
              text: Qt.formatTime(new Date(), "h:mm")
            }

            Item { width: 1; height: composition.step(-1) }

            Text {
              id: date
              anchors.horizontalCenter: parent.horizontalCenter
              color: "#e8eef5"
              opacity: 0.85
              font.family: "Manrope"
              font.weight: Font.Medium
              font.pixelSize: Math.round(composition.step(1))
              text: Qt.formatDate(new Date(), "dddd, MMMM d")
            }

            Timer {
              running: true
              repeat: true
              interval: 1000
              onTriggered: {
                var now = new Date()
                clock.text = Qt.formatTime(now, "h:mm")
                date.text = Qt.formatDate(now, "dddd, MMMM d")
              }
            }
          }

          // Seven-day forecast on clear glass, breathing in and out every ~15 s.
          Rectangle {
            id: forecast
            visible: root.weather !== null
            x: composition.axisX - width / 2
            y: composition.height / composition.phi - height / 2 + composition.driftY
            width: forecastRow.implicitWidth + composition.step(2) * 2
            height: forecastRow.implicitHeight + composition.step(1) * 2
            radius: composition.step(1)
            color: Qt.rgba(0.04, 0.10, 0.20, 0.24)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1

            opacity: 0.12
            SequentialAnimation on opacity {
              running: root.active
              loops: Animation.Infinite
              NumberAnimation { to: 1.0; duration: 7500; easing.type: Easing.InOutSine }
              NumberAnimation { to: 0.12; duration: 7500; easing.type: Easing.InOutSine }
            }

            Row {
              id: forecastRow
              anchors.centerIn: parent
              spacing: composition.step(2)

              // Now.
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: composition.step(0)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.weather ? root.weatherIcon(root.weather.code, root.sunArc.alt < 0) : ""
                  color: "#ffffff"
                  font.family: "JetBrainsMono Nerd Font"
                  font.pixelSize: Math.round(composition.step(3))
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: composition.step(-2)

                  Text {
                    text: root.weather ? root.weather.temp + "°" + root.weather.unit : ""
                    color: "#ffffff"
                    font.family: "Geist"
                    font.weight: Font.Light
                    font.pixelSize: Math.round(composition.step(2))
                  }

                  Text {
                    text: root.weather ? root.weather.desc : ""
                    color: "#e8eef5"
                    opacity: 0.85
                    font.family: "Manrope"
                    font.weight: Font.Medium
                    font.pixelSize: Math.round(composition.step(0))
                  }

                  Text {
                    text: root.weather ? root.weather.place : ""
                    color: "#e8eef5"
                    opacity: 0.6
                    font.family: "Manrope"
                    font.pixelSize: Math.round(composition.step(-1))
                  }
                }
              }

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: composition.step(4)
                color: Qt.rgba(1, 1, 1, 0.18)
              }

              // Next seven days.
              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: composition.step(1)

                Repeater {
                  model: root.weather ? root.weather.days : []

                  Column {
                    required property var modelData
                    required property int index
                    width: composition.step(3)
                    spacing: composition.step(-1)

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.dayName(modelData.date, index)
                      color: "#e8eef5"
                      opacity: 0.85
                      font.family: "Manrope"
                      font.weight: Font.DemiBold
                      font.pixelSize: Math.round(composition.step(0))
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.weatherIcon(modelData.code, false)
                      color: "#ffffff"
                      font.family: "JetBrainsMono Nerd Font"
                      font.pixelSize: Math.round(composition.step(2))
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.high + "°"
                      color: "#ffffff"
                      font.family: "Geist"
                      font.weight: Font.Medium
                      font.pixelSize: Math.round(composition.step(0))
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: modelData.low + "°"
                      color: "#e8eef5"
                      opacity: 0.6
                      font.family: "Geist"
                      font.pixelSize: Math.round(composition.step(0))
                    }
                  }
                }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: composition.step(2)
            text: "bvos.blueview.ai"
            color: "#ffffff"
            opacity: 0.45
            font.family: "Geist"
            font.pixelSize: Math.round(composition.step(-1))
            font.letterSpacing: Math.round(composition.step(-1)) * 0.3
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          property point origin: Qt.point(-1, -1)
          onPositionChanged: function(mouse) {
            if (origin.x < 0) { origin = Qt.point(mouse.x, mouse.y); return }
            if (Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) > 12) root.dismiss("mouse-move")
          }
          onPressed: root.dismiss("mouse-press")
          onWheel: root.dismiss("wheel")
        }
      }
    }
  }

  Variants {
    model: root.desktopEnabled ? Quickshell.screens : []

    PanelWindow {
      id: desk
      required property var modelData
      screen: modelData

      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      // Just above Omarchy's wallpaper and below every window. The empty input
      // mask lets clicks through, so the wallpaper's double-click pickers still work.
      WlrLayershell.namespace: "bvos-live-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}


      Sky {
        anchors.fill: parent
        service: root
        time: root.time
        renderScale: 0.35
      }
    }
  }
}
