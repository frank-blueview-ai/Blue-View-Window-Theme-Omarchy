// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.

import QtQuick

// The Blue View OS sky, shared by the screensaver and the live desktop.
// `service` is the plugin service: it owns the time of day, the sun and moon,
// and the weather- and wind-driven cloud state.
//
// Layers, back to front: the sky, real stars and constellations, real
// satellites, then the sun and moon ovals and clouds (which hide what's behind them).
Item {
  id: sky

  required property var service
  property real time: 0
  // Fraction of screen resolution for the cloud pass; clouds are soft, so
  // low-res renders upscale cleanly and spare the GPU. The sky is smoother still.
  property real renderScale: 0.4

  component Pass: ShaderEffect {
    property real renderScale: 0.4
    property real time: sky.time
    property real aspect: width / Math.max(1, height)
    property vector2d sunPos: Qt.vector2d(sky.service.sunArc.x, sky.service.sunArc.y)
    property real sunAlt: sky.service.sunArc.alt
    property vector2d moonPos: Qt.vector2d(sky.service.moonArc.x, sky.service.moonArc.y)
    property real moonAlt: sky.service.moonArc.alt
    property real moonLight: sky.service.moonFraction
    property real moonWaxing: sky.service.moonWaxing ? 1 : -1
    property real cover: sky.service.skyCover
    property real gloom: sky.service.skyGloom
    property real rain: sky.service.skyRain
    property real snow: sky.service.skySnow
    property real fog: sky.service.skyFog
    property real storm: sky.service.skyStorm
    property vector3d layerShiftX: sky.service.layerShiftX
    property vector3d layerShiftY: sky.service.layerShiftY
    property vector2d highShift: sky.service.highShift

    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(Math.max(1, Math.round(width * renderScale)), Math.max(1, Math.round(height * renderScale)))
  }

  Pass {
    fragmentShader: Qt.resolvedUrl("sky.frag.qsb")
    renderScale: sky.renderScale * 0.5
  }

  StarField {
    anchors.fill: parent
    service: sky.service
  }

  Satellites {
    anchors.fill: parent
    service: sky.service
  }

  Pass {
    fragmentShader: Qt.resolvedUrl("clouds.frag.qsb")
    renderScale: sky.renderScale
  }
}
