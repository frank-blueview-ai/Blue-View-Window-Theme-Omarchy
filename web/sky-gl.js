// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// WebGL 2 renderer for one pass of the shared sky shader (sky.glsl): SKY_PASS
// for the sky itself, CLOUD_PASS for the sun and moon ovals and clouds, drawn
// with premultiplied alpha over the stars. Each pass renders into its own
// canvas at a fraction of screen resolution; the browser upscales it smoothly.

"use strict"

class SkyPass {
  constructor(canvas, pass, transparent) {
    this.canvas = canvas
    this.pass = pass
    this.transparent = transparent
    this.renderScale = 0.4
    this.ready = false
    canvas.addEventListener("webglcontextlost", event => { event.preventDefault(); this.ready = false })
    canvas.addEventListener("webglcontextrestored", () => this.init())
    this.init()
  }

  init() {
    const gl = this.canvas.getContext("webgl2", {
      alpha: this.transparent,
      premultipliedAlpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "low-power"
    })
    if (!gl) throw new Error("WebGL 2 is not available")
    this.gl = gl

    const vertex = `#version 300 es
      in vec2 position;
      out vec2 qt_TexCoord0;
      void main() {
        // Qt's texture coordinates start at the top left.
        qt_TexCoord0 = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
        gl_Position = vec4(position, 0.0, 1.0);
      }`
    const program = gl.createProgram()
    gl.attachShader(program, this.compile(gl.VERTEX_SHADER, vertex))
    gl.attachShader(program, this.compile(gl.FRAGMENT_SHADER, BVOS_SKY_SHADER.fragment(this.pass)))
    gl.bindAttribLocation(program, 0, "position")
    gl.linkProgram(program)
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program))
    gl.useProgram(program)
    this.program = program

    // One triangle covering the screen.
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer())
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
    gl.enableVertexAttribArray(0)
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)

    this.uniforms = {}
    for (const [name, type] of BVOS_SKY_SHADER.uniforms) this.uniforms[name] = { location: gl.getUniformLocation(program, name), type }
    this.ready = true
  }

  compile(type, source) {
    const gl = this.gl
    const shader = gl.createShader(type)
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader))
    return shader
  }

  resize(cssWidth, cssHeight, pixelRatio) {
    const width = Math.max(1, Math.round(cssWidth * pixelRatio * this.renderScale))
    const height = Math.max(1, Math.round(cssHeight * pixelRatio * this.renderScale))
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width
      this.canvas.height = height
    }
  }

  render(values) {
    if (!this.ready) return
    const gl = this.gl
    gl.viewport(0, 0, this.canvas.width, this.canvas.height)
    values.aspect = this.canvas.width / this.canvas.height
    for (const name in this.uniforms) {
      const u = this.uniforms[name]
      if (!u.location || !(name in values)) continue
      const v = values[name]
      if (u.type === "float") gl.uniform1f(u.location, v)
      else if (u.type === "vec2") gl.uniform2f(u.location, v[0], v[1])
      else if (u.type === "vec3") gl.uniform3f(u.location, v[0], v[1], v[2])
    }
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.drawArrays(gl.TRIANGLES, 0, 3)
  }
}
