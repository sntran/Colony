// The picture: WebGL2 on one canvas, with no game engine.
//
// There are four programs: the ground, the water, the bodies and the plain shapes.
// The bodies and the plain shapes use instancing: one draw call for all of them.

import { ROW_STEP, GAP } from "./hex.js";
import { BODY_STRIDE, MESH_STRIDE, FOOD_COLOR } from "./state.js";
import * as shapes from "./geometry.js";

const FOG = [0.66, 0.78, 0.8];
const SUN = [0.42, 0.8, -0.43];

const COMMON = `#version 300 es
precision highp float;
const vec3 SUN = vec3(${SUN.join(",")});
const vec3 FOG = vec3(${FOG.join(",")});
float fogAt(float distance) { return smoothstep(24.0, 62.0, distance); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
`;

const GROUND_VS = `${COMMON}
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
uniform mat4 uViewProj;
out vec3 vPos; out vec3 vNormal; out vec3 vColor;
void main() {
  vPos = aPos; vNormal = aNormal; vColor = aColor;
  gl_Position = uViewProj * vec4(aPos, 1.0);
}`;

const GROUND_FS = `${COMMON}
in vec3 vPos; in vec3 vNormal; in vec3 vColor;
uniform vec3 uEye;
uniform float uTime;
uniform vec2 uGrid;      // width, rows
uniform sampler2D uScent;
uniform sampler2D uBank;  // 1 for a bank cell, 0 for a river cell
out vec4 color;

// The cell of a point: column, row, and the distance from the center (0.5 at the edge).
vec3 cellOf(vec2 p) {
  float r = p.y / ${ROW_STEP};
  float q = p.x - r * 0.5;
  float s = -q - r;
  float rq = floor(q + 0.5), rr = floor(r + 0.5), rs = floor(s + 0.5);
  float dq = abs(rq - q), dr = abs(rr - r), ds = abs(rs - s);
  if (dq > dr && dq > ds) rq = -rr - rs; else if (dr > ds) rr = -rq - rs;
  float odd = mod(rr, 2.0);
  float col = rq + (rr - odd) * 0.5;
  vec2 d = abs(p - vec2(col + 0.5 * odd, rr * ${ROW_STEP}));
  return vec3(col, rr, max(d.x, d.x * 0.5 + d.y * ${ROW_STEP}));
}

void main() {
  vec3 n = normalize(vNormal);
  vec3 c = vColor * (0.86 + 0.28 * (0.6 * noise(vPos.xz * 2.7) + 0.4 * noise(vPos.xz * 9.0 + vPos.y * 5.0)));
  float top = smoothstep(0.75, 0.95, n.y);
  float glow = 0.0;

  vec3 cell = cellOf(vPos.xz);
  if (top > 0.0 && cell.x >= 0.0 && cell.x < uGrid.x && cell.y >= 0.0 && cell.y < uGrid.y &&
      texelFetch(uBank, ivec2(cell.xy), 0).r > 0.5) {
    // A thin line between the cells.
    c *= 1.0 - 0.13 * top * smoothstep(0.455, 0.5, cell.z);
    // Scent: a soft spot of light in the cell.
    float scent = texelFetch(uScent, ivec2(cell.xy), 0).r * 2.55;
    if (scent > 0.0) {
      float spot = 1.0 - smoothstep(0.08, 0.47, cell.z);
      float wave = 0.85 + 0.15 * sin(uTime * 2.5 + cell.x * 1.9 + cell.y * 2.3);
      glow = top * spot * wave * (0.25 + 0.75 * scent);
    }
  }

  float sun = max(dot(n, normalize(SUN)), 0.0);
  c *= 0.5 + 0.62 * sun;
  // The walls of the gap get dark in the direction of the bottom.
  c *= mix(1.0, 0.3, clamp(-vPos.y / 3.4, 0.0, 1.0));
  c = mix(c, vec3(0.93, 0.42, 1.0), glow * 0.66) + vec3(0.22, 0.04, 0.27) * glow;
  color = vec4(mix(c, FOG, fogAt(distance(vPos, uEye))), 1.0);
}`;

const WATER_VS = `${COMMON}
layout(location=0) in vec3 aPos;
uniform mat4 uViewProj;
out vec3 vPos;
void main() { vPos = aPos; gl_Position = uViewProj * vec4(aPos, 1.0); }`;

const WATER_FS = `${COMMON}
in vec3 vPos;
uniform vec3 uEye;
uniform float uTime;
out vec4 color;
void main() {
  vec2 p = vPos.xz;
  float a = noise(p * 0.9 + vec2(uTime * 0.35, uTime * 0.1));
  float b = noise(p * 2.3 - vec2(uTime * 0.5, 0.0));
  float lines = smoothstep(0.62, 0.7, a * 0.6 + b * 0.4);
  vec3 c = mix(vec3(0.05, 0.16, 0.22), vec3(0.1, 0.3, 0.36), a) + vec3(0.25, 0.35, 0.35) * lines * 0.5;
  color = vec4(mix(c, FOG, fogAt(distance(vPos, uEye))), 1.0);
}`;

const BODY_VS = `${COMMON}
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aMove;    // weight, step group, shade
layout(location=3) in vec4 iPos;     // x, y, z, scale
layout(location=4) in vec4 iTurn;    // cos and sin of the heading, not used
layout(location=5) in vec4 iColor;   // red, green, blue, lock
layout(location=6) in vec4 iStep;    // sin and cos of the walk phase, legs, shake
layout(location=7) in vec4 aLock;    // the position in a locked body, and the number of the leg
uniform mat4 uViewProj;
out vec3 vNormal; out vec3 vColor; out vec3 vWorld; out float vLock;
void main() {
  // The page calculates each sine and cosine one time for a body, not for each vertex.
  vec3 p = aPos;
  vec3 n = aNormal;
  float weight = aMove.x;
  float lock = iColor.a;
  if (lock > 0.5) {
    // A locked body is flat and low. Each leg goes to the edge of the cell if a body or a
    // bank is in its direction. If not, the leg stays short.
    p = aLock.xyz;
    if (aLock.w >= 0.0) {
      float there = mod(floor(iStep.z / exp2(aLock.w)), 2.0);
      p.xz *= mix(0.4, 1.0, there);
      n = vec3(0.0, 1.0, 0.0);
    } else {
      n = normalize(vec3(n.x, n.y * 2.0, n.z));
    }
    // A body with not much support shakes.
    p.x += iStep.w;
  } else {
    // The legs move when the body walks. Two groups of three legs move in turn.
    float group = 1.0 - 2.0 * aMove.y;
    p.z += iStep.x * group * 0.075 * weight;
    p.y += max(0.0, iStep.y * group) * 0.055 * weight;
  }
  p *= iPos.w;
  p = vec3(p.x * iTurn.x + p.z * iTurn.y, p.y, -p.x * iTurn.y + p.z * iTurn.x);
  n = vec3(n.x * iTurn.x + n.z * iTurn.y, n.y, -n.x * iTurn.y + n.z * iTurn.x);

  vWorld = p + iPos.xyz;
  vNormal = n;
  vColor = iColor.rgb * aMove.z;
  vLock = lock;
  gl_Position = uViewProj * vec4(vWorld, 1.0);
}`;

const BODY_FS = `${COMMON}
in vec3 vNormal; in vec3 vColor; in vec3 vWorld; in float vLock;
uniform vec3 uEye;
out vec4 color;
void main() {
  vec3 n = normalize(vNormal);
  vec3 view = normalize(uEye - vWorld);
  float sun = max(dot(n, normalize(SUN)), 0.0);
  float shine = pow(max(dot(n, normalize(normalize(SUN) + view)), 0.0), 24.0);
  float rim = pow(1.0 - max(dot(n, view), 0.0), 3.0);
  // A free body shines. A locked body does not: it is a part of a structure.
  float free = 1.0 - vLock;
  vec3 c = vColor * (0.5 + 0.75 * sun) + vec3(0.5) * shine * free + vec3(0.2, 0.22, 0.25) * rim * free;
  color = vec4(mix(c, FOG, fogAt(distance(vWorld, uEye))), 1.0);
}`;

const SHAPE_VS = `${COMMON}
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aTint;    // the color of the vertex; white if the shape has none
layout(location=3) in vec4 iPos;     // x, y, z, turn
layout(location=4) in vec3 iScale;
layout(location=5) in vec4 iColor;
layout(location=6) in float aWind;   // how much the vertex moves in the wind
uniform mat4 uViewProj;
uniform float uTime;
out vec3 vNormal; out vec4 vColor; out vec3 vWorld; out float vUp;
void main() {
  vec3 p = aPos * iScale;
  vec3 n = normalize(aNormal / iScale);
  float c = cos(iPos.w), s = sin(iPos.w);
  p = vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
  n = vec3(n.x * c + n.z * s, n.y, -n.x * s + n.z * c);
  vUp = aPos.y;
  vWorld = p + iPos.xyz;
  // Grass moves in the wind. The top moves more than the bottom.
  vWorld.x += aWind * sin(uTime * 1.7 + vWorld.x * 1.3 + vWorld.z * 0.9);
  vNormal = n;
  vColor = vec4(iColor.rgb * aTint, iColor.a);
  gl_Position = uViewProj * vec4(vWorld, 1.0);
}`;

// Modes: 0 = solid with light, 1 = flat with alpha, 2 = light that fades with height,
// 3 = solid that also gives light (the food).
const SHAPE_FS = `${COMMON}
in vec3 vNormal; in vec4 vColor; in vec3 vWorld; in float vUp;
uniform vec3 uEye;
uniform int uMode;
out vec4 color;
void main() {
  vec3 c = vColor.rgb;
  float alpha = vColor.a;
  float fog = fogAt(distance(vWorld, uEye));
  if (uMode == 0 || uMode == 3) {
    float sun = max(dot(normalize(vNormal), normalize(SUN)), 0.0);
    c *= 0.5 + 0.7 * sun;
    if (uMode == 3) c = c * 0.75 + vColor.rgb * 0.4;
    c = mix(c, FOG, fog * (uMode == 3 ? 0.35 : 1.0));
    alpha = 1.0;
  } else if (uMode == 2) {
    alpha *= (1.0 - vUp) * (1.0 - vUp) * (1.0 - 0.5 * fog);
  } else {
    alpha *= 1.0 - fog;
  }
  color = vec4(c, alpha);
}`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(`Shader error: ${gl.getShaderInfoLog(shader)}`);
  }
  return shader;
}

function program(gl, vertex, fragment, names) {
  const id = gl.createProgram();
  gl.attachShader(id, compile(gl, gl.VERTEX_SHADER, vertex));
  gl.attachShader(id, compile(gl, gl.FRAGMENT_SHADER, fragment));
  gl.linkProgram(id);
  if (!gl.getProgramParameter(id, gl.LINK_STATUS)) {
    throw new Error(`Program error: ${gl.getProgramInfoLog(id)}`);
  }
  const uniforms = {};
  for (const name of names) uniforms[name] = gl.getUniformLocation(id, name);
  return { id, uniforms };
}

function perspective(fov, aspect, near, far) {
  const f = 1 / Math.tan(fov / 2);
  return [f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, (2 * far * near) / (near - far), 0];
}

function multiply(a, b) {
  const out = new Float32Array(16);
  for (let column = 0; column < 4; column++) {
    for (let row = 0; row < 4; row++) {
      let sum = 0;
      for (let k = 0; k < 4; k++) sum += a[k * 4 + row] * b[column * 4 + k];
      out[column * 4 + row] = sum;
    }
  }
  return out;
}

const normalize = (v) => {
  const length = Math.hypot(...v) || 1;
  return v.map((part) => part / length);
};
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    // A screen with many pixels does not need smooth edges from the graphics card. Without
    // them, the picture is faster. A phone has such a screen.
    const antialias = (window.devicePixelRatio || 1) < 2;
    const gl = canvas.getContext("webgl2", { antialias, alpha: false, powerPreference: "high-performance" });
    if (!gl) throw new Error("This browser has no WebGL2.");
    this.gl = gl;
    this.scale = Math.min(window.devicePixelRatio || 1, 2);
    this.ready = false;

    this.ground = program(gl, GROUND_VS, GROUND_FS, ["uViewProj", "uEye", "uTime", "uGrid", "uScent", "uBank"]);
    this.water = program(gl, WATER_VS, WATER_FS, ["uViewProj", "uEye", "uTime"]);
    this.body = program(gl, BODY_VS, BODY_FS, ["uViewProj", "uEye", "uTime"]);
    this.shape = program(gl, SHAPE_VS, SHAPE_FS, ["uViewProj", "uEye", "uTime", "uMode"]);

    this.meshes = {
      body: this.upload(shapes.bodyMesh()),
      blob: this.upload(shapes.blobMesh()),
      disc: this.upload(shapes.discMesh()),
      ring: this.upload(shapes.ringMesh()),
      cell: this.upload(shapes.cellMesh()),
      beam: this.upload(shapes.beamMesh()),
    };

    // One list of instances for each use.
    this.lists = {};
    this.list("bodies", this.meshes.body, BODY_STRIDE);
    for (const [name, mesh] of [
      ["shadows", "disc"], ["crumbs", "blob"], ["rings", "ring"], ["cells", "cell"],
      ["food", "blob"], ["beam", "beam"], ["holes", "disc"], ["decks", "cell"], ["marks", "disc"],
    ]) {
      this.list(name, this.meshes[mesh], MESH_STRIDE);
    }

    this.viewProj = new Float32Array(16);
    this.eye = [0, 1, 0];
    this.basis = null;
  }

  // Puts a shape on the graphics card.
  upload(mesh) {
    const gl = this.gl;
    // With no vertex array active, the index buffer of an other shape does not change.
    gl.bindVertexArray(null);
    const vertices = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vertices);
    gl.bufferData(gl.ARRAY_BUFFER, mesh.vertices, gl.STATIC_DRAW);
    const indices = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indices);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, mesh.indices, gl.STATIC_DRAW);
    return {
      vertices,
      indices,
      stride: mesh.stride,
      count: mesh.indices.length,
      type: mesh.indices instanceof Uint32Array ? gl.UNSIGNED_INT : gl.UNSIGNED_SHORT,
    };
  }

  // Makes a list of instances of one shape.
  list(name, mesh, stride) {
    const gl = this.gl;
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, mesh.vertices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.indices);
    const bytes = mesh.stride * 4;
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, bytes, 0);
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 3, gl.FLOAT, false, bytes, 12);
    if (mesh.stride === 13) {
      gl.enableVertexAttribArray(2);
      gl.vertexAttribPointer(2, 3, gl.FLOAT, false, bytes, 24);
      gl.enableVertexAttribArray(7);
      gl.vertexAttribPointer(7, 4, gl.FLOAT, false, bytes, 36);
    } else {
      // A plain shape has no color for each vertex and does not move in the wind.
      gl.vertexAttrib3f(2, 1, 1, 1);
      gl.vertexAttrib4f(6, 0, 0, 0, 0);
    }
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    const layout = stride === BODY_STRIDE ? [[3, 4, 0], [4, 4, 16], [5, 4, 32], [6, 4, 48]] : [[3, 4, 0], [4, 3, 16], [5, 4, 28]];
    for (const [location, size, offset] of layout) {
      gl.enableVertexAttribArray(location);
      gl.vertexAttribPointer(location, size, gl.FLOAT, false, stride * 4, offset);
      gl.vertexAttribDivisor(location, 1);
    }
    gl.bindVertexArray(null);
    this.lists[name] = { vao, buffer, mesh, stride, count: 0, size: 0 };
  }

  // Sends the instances of a list to the graphics card.
  fill(name, data, count) {
    const gl = this.gl;
    const list = this.lists[name];
    list.count = count;
    if (count === 0) return;
    const length = count * list.stride;
    gl.bindBuffer(gl.ARRAY_BUFFER, list.buffer);
    if (length > list.size) {
      list.size = Math.max(length, data.length);
      gl.bufferData(gl.ARRAY_BUFFER, list.size * 4, gl.DYNAMIC_DRAW);
    }
    gl.bufferSubData(gl.ARRAY_BUFFER, 0, data, 0, length);
  }

  // Makes the ground, the grass, the stones and the nest. This is done one time for a world.
  setWorld(world) {
    const gl = this.gl;
    const grid = world.grid;
    const terrain = shapes.terrainMesh(grid, world.seed);
    this.terrain = this.upload(terrain);
    this.terrainVao = gl.createVertexArray();
    gl.bindVertexArray(this.terrainVao);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.terrain.vertices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.terrain.indices);
    for (let i = 0; i < 3; i++) {
      gl.enableVertexAttribArray(i);
      gl.vertexAttribPointer(i, 3, gl.FLOAT, false, 36, i * 12);
    }

    // The water is below all the places where the river can be.
    const nearEdge = (grid.nearRows - 1) * ROW_STEP;
    const farEdge = (grid.nearRows + Math.max(...grid.river)) * ROW_STEP;
    const pad = terrain.columns;
    const y = -shapes.GAP_DEPTH;
    const water = this.upload({
      vertices: new Float32Array([-pad, y, nearEdge - 1, grid.width + pad, y, nearEdge - 1, grid.width + pad, y, farEdge + 1, -pad, y, farEdge + 1]),
      indices: new Uint16Array([0, 1, 2, 0, 2, 3]),
      stride: 3,
    });
    this.waterMesh = water;
    this.waterVao = gl.createVertexArray();
    gl.bindVertexArray(this.waterVao);
    gl.bindBuffer(gl.ARRAY_BUFFER, water.vertices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, water.indices);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 12, 0);
    gl.bindVertexArray(null);

    // One number for each cell: 255 for a bank cell. The ground shader draws the lines
    // of the cells and the scent only there.
    const bank = new Uint8Array(grid.count);
    for (let cell = 0; cell < grid.count; cell++) bank[cell] = grid.kind(cell) === GAP ? 0 : 255;
    this.bankTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, this.bankTexture);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, grid.width, grid.rows, 0, gl.RED, gl.UNSIGNED_BYTE, bank);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

    this.scentTexture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, this.scentTexture);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, grid.width, grid.rows, 0, gl.RED, gl.UNSIGNED_BYTE, world.scent);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

    this.decorate(world, terrain);
    this.grid = grid;
    this.ready = true;
  }

  // Puts the shape of the things that do not move on the graphics card.
  setScenery(vertices, indices) {
    const gl = this.gl;
    this.scenery = this.upload({ vertices, indices, stride: 10 });
    this.sceneryVao = gl.createVertexArray();
    gl.bindVertexArray(this.sceneryVao);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.scenery.vertices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.scenery.indices);
    for (const [location, size, offset] of [[0, 3, 0], [1, 3, 12], [2, 3, 24], [6, 1, 36]]) {
      gl.enableVertexAttribArray(location);
      gl.vertexAttribPointer(location, size, gl.FLOAT, false, 40, offset);
    }
    // This shape has no instances: one position, one size and one color for all of it.
    gl.vertexAttrib4f(3, 0, 0, 0, 0);
    gl.vertexAttrib3f(4, 1, 1, 1);
    gl.vertexAttrib4f(5, 1, 1, 1, 1);
    gl.bindVertexArray(null);
  }

  // Grass, stones and the nest, from the seed of the world.
  decorate(world, terrain) {
    const grid = world.grid;
    const height = terrain.height;
    const random = shapes.randomFrom(world.seed ^ 0x51ed);
    const zEnd = (grid.rows - 1) * ROW_STEP;
    const nest = [grid.x(world.nest), grid.z(world.nest)];
    this.nest = nest;
    this.grid = grid;
    const clear = (x, z) => Math.hypot(x - nest[0], z - nest[1]) > 1.1;
    // A random point on one of the two banks, `margin` cells or less outside of the grid.
    const point = (margin) => {
      for (;;) {
        const x = -margin + random() * (grid.width + 2 * margin);
        const z = -margin + random() * (zEnd + 2 * margin);
        const row = Math.round(z / ROW_STEP);
        const col = Math.round(x - 0.5 * (row & 1));
        // Not on the river, and not on the last part of a cell at the river.
        if (terrain.isBank(row, col) && terrain.isBank(row + 1, col) && terrain.isBank(row - 1, col)) return [x, z];
      }
    };
    // The grass, the stones and the nest do not move. They are one shape, made one time:
    // position (3), normal (3), color (3) and wind (1) for each vertex.
    const vertices = [];
    const indices = [];
    const add = (mesh, x, yy, z, turn, sx, sy, sz, color, wind) => {
      const base = vertices.length / 10;
      const cos = Math.cos(turn);
      const sin = Math.sin(turn);
      const source = mesh.vertices;
      for (let i = 0; i < source.length; i += 6) {
        const px = source[i] * sx;
        const py = source[i + 1] * sy;
        const pz = source[i + 2] * sz;
        const nx = source[i + 3] / sx;
        const ny = source[i + 4] / sy;
        const nz = source[i + 5] / sz;
        const length = Math.hypot(nx, ny, nz) || 1;
        vertices.push(
          x + px * cos + pz * sin, yy + py, z - px * sin + pz * cos,
          (nx * cos + nz * sin) / length, ny / length, (-nx * sin + nz * cos) / length,
          color[0], color[1], color[2], wind * py
        );
      }
      for (const index of mesh.indices) indices.push(base + index);
    };

    const blade = shapes.grassMesh();
    for (let i = 0; i < 5200; i++) {
      const [x, z] = point(7);
      if (!clear(x, z)) continue;
      const size = 0.8 + random() * 1.1;
      const tone = random();
      add(blade, x, height(x, z), z, random() * 6.28, size, size * (0.8 + random() * 0.6), size, [0.3 + tone * 0.22, 0.52 + tone * 0.16, 0.18 + tone * 0.05], 0.45);
    }

    const blob = shapes.blobMesh();
    for (let i = 0; i < 230; i++) {
      // Small stones on the cells, large stones on the land around the cells.
      const large = i >= 150;
      const [x, z] = point(large ? 16 : 0);
      const inside = x > -1 && x < grid.width + 1 && z > -1 && z < zEnd + 1;
      if (!clear(x, z) || (large && inside)) continue;
      const size = large ? 0.5 + random() * 1.3 : 0.07 + random() * 0.13;
      const tone = 0.42 + random() * 0.2;
      add(blob, x, height(x, z) + size * 0.2, z, random() * 6.28, size * (0.8 + random() * 0.5), size * (0.5 + random() * 0.3), size, [tone, tone * 0.95, tone * 0.9], 0);
    }
    // The nest: a ring of earth around a dark hole.
    for (let i = 0; i < 13; i++) {
      const angle = (i / 13) * 6.283;
      const size = 0.2 + random() * 0.1;
      add(blob, nest[0] + Math.cos(angle) * 0.62, 0.02, nest[1] + Math.sin(angle) * 0.62, random() * 6.28, size * 1.25, size * 0.8, size * 1.1, [0.46 + random() * 0.06, 0.33, 0.2], 0);
    }
    this.setScenery(new Float32Array(vertices), new Uint32Array(indices));


    // The places of the pieces of food in the pile and at the nest. The low pieces are first.
    const heap = (count, radius, top) => {
      const pieces = [];
      for (let i = 0; i < count; i++) {
        const r = radius * Math.sqrt(random());
        const angle = random() * 6.283;
        pieces.push([Math.cos(angle) * r, (1 - r / radius) * top * (0.3 + 0.7 * random()), Math.sin(angle) * r, random() * 6.28, 0.75 + random() * 0.5]);
      }
      return pieces.sort((a, b) => a[1] - b[1]);
    };
    this.pilePieces = heap(56, 0.95, 0.95);
    this.nestPieces = heap(40, 0.45, 0.4);
  }

  // The pile of food, the light above it, and the food at the nest.
  setFood(world) {
    const grid = world.grid;
    const at = [grid.x(world.pile.cell), grid.z(world.pile.cell)];
    const data = [];
    const pileCount = Math.ceil((world.pile.units / Math.max(1, world.pileUnits)) * this.pilePieces.length);
    const nestCount = Math.min(this.nestPieces.length, world.foodNest);
    const add = (pieces, count, x, z, size) => {
      for (let i = 0; i < count; i++) {
        const [px, py, pz, turn, scale] = pieces[i];
        const s = size * scale;
        data.push(x + px, py + s * 0.55, z + pz, turn, s, s * 0.85, s, FOOD_COLOR[0], FOOD_COLOR[1] + 0.08 * Math.sin(i), FOOD_COLOR[2], 1);
      }
    };
    add(this.pilePieces, pileCount, at[0], at[1], 0.21);
    add(this.nestPieces, nestCount, this.nest[0] - 1.15, this.nest[1] + 0.25, 0.11);
    this.fill("food", new Float32Array(data), data.length / MESH_STRIDE);
    const beam = world.pile.units > 0 ? [at[0], 0.2, at[1], 0.6, 0.36, 9, 0.36, 1.0, 0.82, 0.4, 0.34] : [];
    this.fill("beam", new Float32Array(beam), beam.length / MESH_STRIDE);
    // The dark hole of the nest and the shadow of the pile.
    const holes = [
      this.nest[0], 0.035, this.nest[1], 0, 0.52, 1, 0.52, 0.07, 0.05, 0.04, 0.92,
      at[0], 0.02, at[1], 0, 1.25, 1, 1.25, 0, 0, 0, 0.22,
    ];
    this.fill("holes", new Float32Array(holes), 2);
  }

  setScent(world) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, this.scentTexture);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, world.grid.width, world.grid.rows, gl.RED, gl.UNSIGNED_BYTE, world.scent);
  }

  // Makes the canvas the size of the window. `scale` is the number of pixels of the
  // canvas for each pixel of the page.
  resize() {
    const canvas = this.canvas;
    const width = Math.max(1, Math.round(canvas.clientWidth * this.scale));
    const height = Math.max(1, Math.round(canvas.clientHeight * this.scale));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
  }

  // camera: { x, z, turn, height, distance, fov }. The camera looks at the point x, z on
  // the ground from behind and above.
  setCamera(camera) {
    const aspect = this.canvas.width / this.canvas.height;
    const eye = [camera.x - Math.sin(camera.turn) * camera.distance, camera.height, camera.z - Math.cos(camera.turn) * camera.distance];
    const forward = normalize([camera.x - eye[0], -eye[1], camera.z - eye[2]]);
    const right = normalize(cross(forward, [0, 1, 0]));
    const up = cross(right, forward);
    const view = [
      right[0], up[0], -forward[0], 0,
      right[1], up[1], -forward[1], 0,
      right[2], up[2], -forward[2], 0,
      -dot(right, eye), -dot(up, eye), dot(forward, eye), 1,
    ];
    this.viewProj = multiply(perspective(camera.fov, aspect, 0.5, 140), view);
    this.eye = eye;
    this.basis = { forward, right, up, tan: Math.tan(camera.fov / 2), aspect };
  }

  // The position on the page of a point of the world, or null if the point is behind the camera.
  project(x, y, z) {
    const m = this.viewProj;
    const w = m[3] * x + m[7] * y + m[11] * z + m[15];
    if (w <= 0.01) return null;
    const px = (m[0] * x + m[4] * y + m[8] * z + m[12]) / w;
    const py = (m[1] * x + m[5] * y + m[9] * z + m[13]) / w;
    return [(px * 0.5 + 0.5) * this.canvas.clientWidth, (0.5 - py * 0.5) * this.canvas.clientHeight];
  }

  // True if a point on the ground is in the picture, with a margin for the size of a body.
  sees(x, z) {
    const m = this.viewProj;
    const w = m[3] * x + m[11] * z + m[15];
    if (w <= 0.01) return false;
    const limit = w + 1.2;
    const px = m[0] * x + m[8] * z + m[12];
    const py = m[1] * x + m[9] * z + m[13];
    return px > -limit && px < limit && py > -limit && py < limit;
  }

  // The point of the world at the height `y` below a position on the page.
  pick(pageX, pageY, y) {
    const { forward, right, up, tan, aspect } = this.basis;
    const nx = (pageX / this.canvas.clientWidth) * 2 - 1;
    const ny = 1 - (pageY / this.canvas.clientHeight) * 2;
    const direction = [0, 1, 2].map((i) => forward[i] + right[i] * nx * tan * aspect + up[i] * ny * tan);
    if (direction[1] >= -0.0001) return null;
    const t = (y - this.eye[1]) / direction[1];
    return [this.eye[0] + direction[0] * t, this.eye[2] + direction[2] * t];
  }

  draw(world, time) {
    const gl = this.gl;
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.clearColor(FOG[0], FOG[1], FOG[2], 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    if (!this.ready) return;
    gl.enable(gl.DEPTH_TEST);
    gl.disable(gl.BLEND);
    gl.depthMask(true);

    const start = (item) => {
      gl.useProgram(item.id);
      gl.uniformMatrix4fv(item.uniforms.uViewProj, false, this.viewProj);
      gl.uniform3fv(item.uniforms.uEye, this.eye);
      gl.uniform1f(item.uniforms.uTime, time);
    };
    const instances = (name) => {
      const list = this.lists[name];
      if (list.count === 0) return;
      gl.bindVertexArray(list.vao);
      gl.drawElementsInstanced(gl.TRIANGLES, list.mesh.count, list.mesh.type, 0, list.count);
    };

    // The ground and the water.
    const grid = this.grid;
    start(this.ground);
    gl.uniform2f(this.ground.uniforms.uGrid, grid.width, grid.rows);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, this.bankTexture);
    gl.uniform1i(this.ground.uniforms.uBank, 1);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.scentTexture);
    gl.uniform1i(this.ground.uniforms.uScent, 0);
    gl.bindVertexArray(this.terrainVao);
    gl.drawElements(gl.TRIANGLES, this.terrain.count, this.terrain.type, 0);

    start(this.water);
    gl.bindVertexArray(this.waterVao);
    gl.drawElements(gl.TRIANGLES, this.waterMesh.count, this.waterMesh.type, 0);

    // Solid shapes.
    start(this.shape);
    gl.uniform1i(this.shape.uniforms.uMode, 0);
    gl.bindVertexArray(this.sceneryVao);
    gl.drawElements(gl.TRIANGLES, this.scenery.count, this.scenery.type, 0);
    gl.uniform1i(this.shape.uniforms.uMode, 3);
    instances("food");
    instances("crumbs");

    // Flat marks on the ground: they mix with the ground and do not hide the bodies.
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.depthMask(false);
    gl.uniform1i(this.shape.uniforms.uMode, 1);
    instances("holes");
    instances("decks");
    gl.depthMask(true);
    gl.disable(gl.BLEND);

    start(this.body);
    instances("bodies");

    // The shadows of the free bodies, on the ground and on the bodies of a bridge.
    gl.enable(gl.BLEND);
    gl.depthMask(false);
    start(this.shape);
    gl.uniform1i(this.shape.uniforms.uMode, 1);
    instances("shadows");

    // The marks of the cells where a lock is possible, the marks of the reach, and the
    // light above the pile.
    instances("cells");
    instances("rings");
    instances("marks");
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    gl.uniform1i(this.shape.uniforms.uMode, 2);
    instances("beam");
    gl.depthMask(true);
    gl.disable(gl.BLEND);
    gl.bindVertexArray(null);
  }
}
