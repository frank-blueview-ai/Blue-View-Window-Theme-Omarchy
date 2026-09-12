// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// Positional astronomy and atmospheric physics for the Blue View OS sky.
// Sun and moon positions use the standard low-precision ephemeris formulas
// (Astronomical Algorithms, J. Meeus; accurate to a fraction of a degree), and
// cloud motion uses the wind power law and the geometry of a fixed viewpoint.

.pragma library

var RAD = Math.PI / 180
var DAY_MS = 86400000
var J1970 = 2440588
var J2000 = 2451545
var OBLIQUITY = RAD * 23.4397

function toDays(date) {
  return date.valueOf() / DAY_MS - 0.5 + J1970 - J2000
}

function rightAscension(l, b) {
  return Math.atan2(Math.sin(l) * Math.cos(OBLIQUITY) - Math.tan(b) * Math.sin(OBLIQUITY), Math.cos(l))
}

function declination(l, b) {
  return Math.asin(Math.sin(b) * Math.cos(OBLIQUITY) + Math.cos(b) * Math.sin(OBLIQUITY) * Math.sin(l))
}

// Azimuth measured from south, positive toward west (radians).
function azimuth(h, phi, dec) {
  return Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi))
}

function altitude(h, phi, dec) {
  return Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(h))
}

// Local sidereal time (radians) for west longitude lw.
function siderealTime(d, lw) {
  return RAD * (280.16 + 360.9856235 * d) - lw
}

// Atmospheric refraction lifts bodies near the horizon (Sæmundsson).
function refraction(h) {
  if (h < 0) h = 0
  return 0.0002967 / Math.tan(h + 0.00312536 / (h + 0.08901179))
}

function sunCoords(d) {
  var m = RAD * (357.5291 + 0.98560028 * d)
  var c = RAD * (1.9148 * Math.sin(m) + 0.02 * Math.sin(2 * m) + 0.0003 * Math.sin(3 * m))
  var l = m + c + RAD * 102.9372 + Math.PI
  return { dec: declination(l, 0), ra: rightAscension(l, 0) }
}

function moonCoords(d) {
  var l = RAD * (218.316 + 13.176396 * d)
  var m = RAD * (134.963 + 13.064993 * d)
  var f = RAD * (93.272 + 13.229350 * d)
  var lon = l + RAD * 6.289 * Math.sin(m)
  var lat = RAD * 5.128 * Math.sin(f)
  return { ra: rightAscension(lon, lat), dec: declination(lon, lat), dist: 385001 - 20905 * Math.cos(m) }
}

// { azimuth, altitude } in radians; azimuth from south, positive west.
function sunPosition(date, lat, lon) {
  var lw = RAD * -lon
  var phi = RAD * lat
  var d = toDays(date)
  var c = sunCoords(d)
  var h = siderealTime(d, lw) - c.ra
  var alt = altitude(h, phi, c.dec)
  return { azimuth: azimuth(h, phi, c.dec), altitude: alt + refraction(alt) }
}

function moonPosition(date, lat, lon) {
  var lw = RAD * -lon
  var phi = RAD * lat
  var d = toDays(date)
  var c = moonCoords(d)
  var h = siderealTime(d, lw) - c.ra
  var alt = altitude(h, phi, c.dec)
  return { azimuth: azimuth(h, phi, c.dec), altitude: alt + refraction(alt) }
}

// fraction: illuminated 0..1; waxing: true while growing toward full.
function moonIllumination(date) {
  var d = toDays(date)
  var s = sunCoords(d)
  var m = moonCoords(d)
  var sunDist = 149598000
  var phi = Math.acos(Math.sin(s.dec) * Math.sin(m.dec) + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra))
  var inc = Math.atan2(sunDist * Math.sin(phi), m.dist - sunDist * Math.cos(phi))
  var angle = Math.atan2(Math.cos(s.dec) * Math.sin(s.ra - m.ra),
                         Math.sin(s.dec) * Math.cos(m.dec) - Math.cos(s.dec) * Math.sin(m.dec) * Math.cos(s.ra - m.ra))
  var phase = 0.5 + 0.5 * inc * (angle < 0 ? -1 : 1) / Math.PI
  return { fraction: (1 + Math.cos(inc)) / 2, waxing: phase < 0.5 }
}

function localSiderealTime(date, lon) {
  var lst = siderealTime(toDays(date), RAD * -lon) % (2 * Math.PI)
  return lst < 0 ? lst + 2 * Math.PI : lst
}

// ---- Viewpoint and projection ------------------------------------------------
//
// The view is a cylindrical panorama facing the equator (south in the northern
// hemisphere), spanning 200° across a 16:9 screen, from a viewpoint 1 km above
// the tops of a sea of clouds. Angles map linearly to screen units, where one
// unit is the screen height. The horizon sits 0.40 up from the bottom.

var HORIZONTAL_FOV = 200 * RAD
var REFERENCE_ASPECT = 16 / 9
var UNITS_PER_RADIAN = REFERENCE_ASPECT / HORIZONTAL_FOV
var HORIZON_Y = 0.40
var HEIGHT_ABOVE_CLOUDS = 1000     // m, viewer above the cloud tops
var CLOUD_TOP_ALTITUDE = 1500      // m, typical marine stratocumulus tops
var HIGH_CLOUD_ABOVE_VIEWER = 2500 // m, altocumulus drifting overhead
var HIGH_CLOUD_ELEVATION = 30 * RAD

// Screen position for a body: x as an offset from screen center, y from the bottom.
function project(position, lat) {
  // Facing south, west (positive azimuth) is to the right; facing north it's flipped.
  var az = lat >= 0 ? position.azimuth : -wrapAngle(position.azimuth + Math.PI)
  return {
    x: az * UNITS_PER_RADIAN,
    y: HORIZON_Y + position.altitude * UNITS_PER_RADIAN,
    alt: Math.sin(position.altitude)
  }
}

function wrapAngle(a) {
  while (a > Math.PI) a -= 2 * Math.PI
  while (a < -Math.PI) a += 2 * Math.PI
  return a
}

// Wind speed at height z from the 10 m surface wind (power law, exponent 1/7).
function windAt(surfaceMetersPerSecond, z) {
  return surfaceMetersPerSecond * Math.pow(z / 10, 1 / 7)
}

// Wind in the viewer's frame: `right` across the screen and `away` from the
// viewer, in m/s. Meteorological direction is where the wind blows FROM.
function windComponents(speed, fromDegrees, lat) {
  var toward = (fromDegrees + 180) * RAD
  var east = Math.sin(toward) * speed
  var north = Math.cos(toward) * speed
  return lat >= 0 ? { right: -east, away: -north } : { right: east, away: north }
}

// Screen velocity (units/s) of cloud features seen at a depression angle below
// the horizon, for a cloud deck `height` meters below the viewer.
//  - Across: angular speed v / r, with line-of-sight distance r = h / sin(d).
//  - Toward the horizon: d changes at -v_away · sin²(d) / h.
function cloudDeckVelocity(wind, depression, height) {
  var s = Math.sin(depression)
  return {
    x: wind.right * s / height * UNITS_PER_RADIAN,
    y: wind.away * s * s / height * UNITS_PER_RADIAN
  }
}

// The three cloud-sea layers in the shader sit 0, 0.11 and 0.22 units below
// the horizon; the farthest is taken a couple of degrees down.
function layerDepressions() {
  return [2.5 * RAD, 0.11 / UNITS_PER_RADIAN, 0.22 / UNITS_PER_RADIAN]
}

// Velocities (units/s) for the cloud sea layers and the high clouds overhead.
function cloudVelocities(surfaceKmph, fromDegrees, lat) {
  var surface = surfaceKmph / 3.6
  var low = windComponents(windAt(surface, CLOUD_TOP_ALTITUDE), fromDegrees, lat)
  var high = windComponents(windAt(surface, CLOUD_TOP_ALTITUDE + HEIGHT_ABOVE_CLOUDS + HIGH_CLOUD_ABOVE_VIEWER), fromDegrees, lat)
  var layers = layerDepressions().map(function(d) { return cloudDeckVelocity(low, d, HEIGHT_ABOVE_CLOUDS) })
  var s = Math.sin(HIGH_CLOUD_ELEVATION)
  return {
    layers: layers,
    high: { x: high.right * s / HIGH_CLOUD_ABOVE_VIEWER * UNITS_PER_RADIAN, y: -high.away * s * s / HIGH_CLOUD_ABOVE_VIEWER * UNITS_PER_RADIAN }
  }
}

// ---- Stars ------------------------------------------------------------------

// Precess J2000 coordinates (degrees) to the date, first-order IAU 1976 rates.
function precess(raDeg, decDeg, date) {
  var years = (date.valueOf() - Date.UTC(2000, 0, 1, 12)) / (365.25 * DAY_MS)
  var ra = raDeg * RAD
  var dec = decDeg * RAD
  var m = 46.1244 * years / 3600 * RAD
  var n = 20.0431 * years / 3600 * RAD
  return { ra: ra + m + n * Math.sin(ra) * Math.tan(dec), dec: dec + n * Math.cos(ra) }
}

// Horizontal coordinates for equatorial ones (radians), given local sidereal time and latitude.
function horizontal(ra, dec, lst, phi) {
  var h = lst - ra
  var alt = altitude(h, phi, dec)
  return { azimuth: azimuth(h, phi, dec), altitude: alt + refraction(alt) }
}

function lerpTable(table, x) {
  if (x <= table[0][0]) return table[0][1]
  for (var i = 1; i < table.length; i++) {
    if (x <= table[i][0]) {
      var a = table[i - 1]
      var b = table[i]
      return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
    }
  }
  return table[table.length - 1][1]
}

// Faintest star the eye can see, from the sun's altitude (degrees), moonlight
// and weather. Dark-sky limit 5.5; roughly 1 at the end of civil twilight
// (-6°), 3.5 at nautical (-12°), full darkness at astronomical (-18°).
function limitingMagnitude(sunAltitudeDeg, moonAltitudeDeg, moonFraction, gloom) {
  var lim = lerpTable([[-18, 5.5], [-12, 3.5], [-6, 1.0], [0, -2.0], [10, -4.5]], sunAltitudeDeg)
  if (moonAltitudeDeg > 0) lim -= 1.8 * moonFraction * Math.sqrt(Math.sin(moonAltitudeDeg * RAD))
  return lim - gloom * 3.5
}

// Star color from its B-V index (Ballesteros temperature, then blackbody-ish RGB).
function starColor(bv) {
  var t = 4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62))
  var k = t / 100
  var r, g, b
  if (k <= 66) {
    r = 255
    g = 99.47 * Math.log(k) - 161.12
    b = k <= 19 ? 0 : 138.52 * Math.log(k - 10) - 305.04
  } else {
    r = 329.7 * Math.pow(k - 60, -0.1332)
    g = 288.12 * Math.pow(k - 60, -0.0755)
    b = 255
  }
  function clamp(v) { return Math.max(0, Math.min(255, v)) }
  // Pastel toward white, as the eye perceives star colors.
  return [0.55 * clamp(r) + 0.45 * 255, 0.55 * clamp(g) + 0.45 * 255, 0.55 * clamp(b) + 0.45 * 255]
}

// ---- Satellites ---------------------------------------------------------------

// Unit vector toward the sun in the Earth-centered equatorial frame.
function sunDirection(date) {
  var c = sunCoords(toDays(date))
  return [Math.cos(c.dec) * Math.cos(c.ra), Math.cos(c.dec) * Math.sin(c.ra), Math.sin(c.dec)]
}

// Whether a satellite (ECI position in km) is in sunlight, outside Earth's cylindrical shadow.
function sunlit(position, sun) {
  var along = position.x * sun[0] + position.y * sun[1] + position.z * sun[2]
  if (along > 0) return true
  var px = position.x - along * sun[0]
  var py = position.y - along * sun[1]
  var pz = position.z - along * sun[2]
  return Math.sqrt(px * px + py * py + pz * pz) > 6371
}

// Apparent magnitude from standard magnitude (at 1000 km, half lit) and range.
function satelliteMagnitude(standardMagnitude, rangeKm) {
  return standardMagnitude + 5 * Math.log(rangeKm / 1000) / Math.LN10
}
