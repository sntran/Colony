// All the shapes of the game. Each shape comes from code: there are no model files.

import { ROW_STEP } from "./hex.js";

// A random number generator with a seed. The same seed gives the same ground.
export function randomFrom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Smooth noise in two dimensions, from 0 to 1.
export function noiseFrom(seed) {
  const hash = (x, y) => {
    let h = Math.imul(x, 374761393) ^ Math.imul(y, 668265263) ^ seed;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  };
  const noise = (x, y) => {
    const xi = Math.floor(x);
    const yi = Math.floor(y);
    const xf = x - xi;
    const yf = y - yi;
    const u = xf * xf * (3 - 2 * xf);
    const v = yf * yf * (3 - 2 * yf);
    const a = hash(xi, yi);
    const b = hash(xi + 1, yi);
    const c = hash(xi, yi + 1);
    const d = hash(xi + 1, yi + 1);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  };
  return (x, y) => 0.55 * noise(x, y) + 0.3 * noise(x * 2.1 + 9, y * 2.1 + 4) + 0.15 * noise(x * 4.3, y * 4.3 + 7);
}

// ---------------------------------------------------------------------------
// The body: three ellipsoids and six legs.
//
// Each vertex has: position (3), normal (3), and three values for the movement:
// weight (0 at the body, 1 at the foot), step group (0 or 1) and shade.

function ellipsoid(out, center, radius, shade) {
  const segments = 8;
  const rings = 5;
  const base = out.vertices.length / 9;
  for (let ring = 0; ring <= rings; ring++) {
    const v = (ring / rings) * Math.PI;
    for (let segment = 0; segment <= segments; segment++) {
      const u = (segment / segments) * 2 * Math.PI;
      const nx = Math.sin(v) * Math.cos(u);
      const ny = Math.cos(v);
      const nz = Math.sin(v) * Math.sin(u);
      // The normal of an ellipsoid: the direction divided by the radius.
      const length = Math.hypot(nx / radius[0], ny / radius[1], nz / radius[2]);
      out.vertices.push(
        center[0] + nx * radius[0], center[1] + ny * radius[1], center[2] + nz * radius[2],
        nx / radius[0] / length, ny / radius[1] / length, nz / radius[2] / length,
        0, 0, shade
      );
    }
  }
  for (let ring = 0; ring < rings; ring++) {
    for (let segment = 0; segment < segments; segment++) {
      const a = base + ring * (segments + 1) + segment;
      const b = a + segments + 1;
      if (ring > 0) out.indices.push(a, a + 1, b);
      if (ring < rings - 1) out.indices.push(a + 1, b + 1, b);
    }
  }
}

// One part of a leg: a thin bar with three sides.
function bar(out, from, to, weightFrom, weightTo, group, thickness) {
  const base = out.vertices.length / 9;
  const axis = [to[0] - from[0], to[1] - from[1], to[2] - from[2]];
  const length = Math.hypot(...axis);
  const a = axis.map((part) => part / length);
  // Two directions at a right angle to the bar.
  let u = Math.abs(a[1]) < 0.9 ? [a[2], 0, -a[0]] : [1, 0, 0];
  const uLength = Math.hypot(...u);
  u = u.map((part) => part / uLength);
  const v = [a[1] * u[2] - a[2] * u[1], a[2] * u[0] - a[0] * u[2], a[0] * u[1] - a[1] * u[0]];
  for (const [point, weight, size] of [[from, weightFrom, thickness], [to, weightTo, thickness * 0.7]]) {
    for (let side = 0; side < 3; side++) {
      const angle = (side / 3) * 2 * Math.PI;
      const n = [0, 1, 2].map((i) => u[i] * Math.cos(angle) + v[i] * Math.sin(angle));
      out.vertices.push(point[0] + n[0] * size, point[1] + n[1] * size, point[2] + n[2] * size, n[0], n[1], n[2], weight, group, 0.55);
    }
  }
  for (let side = 0; side < 3; side++) {
    const next = (side + 1) % 3;
    out.indices.push(base + side, base + 3 + side, base + next, base + next, base + 3 + side, base + 3 + next);
  }
}

export function bodyMesh() {
  const out = { vertices: [], indices: [] };
  // The front of the body is in the +z direction. The feet are at y = 0.
  ellipsoid(out, [0, 0.13, -0.23], [0.125, 0.105, 0.2], 0.92);
  ellipsoid(out, [0, 0.12, 0.02], [0.075, 0.07, 0.115], 1.0);
  ellipsoid(out, [0, 0.135, 0.2], [0.09, 0.075, 0.09], 1.08);

  // hip, knee, foot of the three legs on one side.
  const legs = [
    [[0.05, 0.11, 0.09], [0.17, 0.2, 0.19], [0.27, 0, 0.3]],
    [[0.06, 0.11, 0.02], [0.21, 0.21, 0.02], [0.33, 0, 0.0]],
    [[0.05, 0.11, -0.05], [0.18, 0.2, -0.16], [0.28, 0, -0.32]],
  ];
  legs.forEach(([hip, knee, foot], index) => {
    for (const side of [1, -1]) {
      // Three legs move together: front and back of one side with the middle of the other side.
      const group = (index + (side > 0 ? 0 : 1)) % 2;
      const mirror = (point) => [point[0] * side, point[1], point[2]];
      bar(out, mirror(hip), mirror(knee), 0, 0.5, group, 0.02);
      bar(out, mirror(knee), mirror(foot), 0.5, 1, group, 0.016);
    }
  });
  return { vertices: new Float32Array(out.vertices), indices: new Uint16Array(out.indices), stride: 9 };
}

// ---------------------------------------------------------------------------
// Plain shapes: position (3) and normal (3).

function plain(vertices, indices) {
  return { vertices: new Float32Array(vertices), indices: new Uint16Array(indices), stride: 6 };
}

// A rough ball with 32 faces. Stones, food and the nest use it.
export function blobMesh() {
  const corners = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
  const faces = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]];
  const vertices = [];
  const indices = [];
  const add = (p) => {
    const length = Math.hypot(...p);
    const n = p.map((part) => part / length);
    vertices.push(...n, ...n);
    return vertices.length / 6 - 1;
  };
  const middle = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2];
  for (const [i, j, k] of faces) {
    const a = corners[i];
    const b = corners[j];
    const c = corners[k];
    const ab = middle(a, b);
    const bc = middle(b, c);
    const ca = middle(c, a);
    for (const triangle of [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]) {
      indices.push(...triangle.map(add));
    }
  }
  return plain(vertices, indices);
}

// A flat disc on the ground.
export function discMesh() {
  const vertices = [0, 0, 0, 0, 1, 0];
  const indices = [];
  const sides = 12;
  for (let i = 0; i < sides; i++) {
    const angle = (i / sides) * 2 * Math.PI;
    vertices.push(Math.cos(angle), 0, Math.sin(angle), 0, 1, 0);
    indices.push(0, 1 + ((i + 1) % sides), 1 + i);
  }
  return plain(vertices, indices);
}

// The corner `i` of a cell with the center at 0, 0.
function corner(i, size) {
  const angle = (i / 6) * 2 * Math.PI + Math.PI / 6;
  return [(Math.cos(angle) * size) / Math.sqrt(3), (Math.sin(angle) * size) / Math.sqrt(3)];
}

// The outline of a cell.
export function ringMesh(inner = 0.74, outer = 0.94) {
  const vertices = [];
  const indices = [];
  for (let i = 0; i < 6; i++) {
    const [ax, az] = corner(i, inner);
    const [bx, bz] = corner(i, outer);
    vertices.push(ax, 0, az, 0, 1, 0, bx, 0, bz, 0, 1, 0);
    const next = ((i + 1) % 6) * 2;
    indices.push(i * 2, next, i * 2 + 1, i * 2 + 1, next, next + 1);
  }
  return plain(vertices, indices);
}

// A full cell.
export function cellMesh(size = 0.9) {
  const vertices = [0, 0, 0, 0, 1, 0];
  const indices = [];
  for (let i = 0; i < 6; i++) {
    const [x, z] = corner(i, size);
    vertices.push(x, 0, z, 0, 1, 0);
    indices.push(0, 1 + ((i + 1) % 6), 1 + i);
  }
  return plain(vertices, indices);
}

// Three blades of grass.
export function grassMesh() {
  const vertices = [];
  const indices = [];
  const blades = [[0, 0, 0.0, 1.0], [0.05, 0.03, 2.1, 0.8], [-0.04, 0.04, 4.2, 0.9]];
  for (const [x, z, angle, height] of blades) {
    const base = vertices.length / 6;
    const dx = Math.cos(angle) * 0.03;
    const dz = Math.sin(angle) * 0.03;
    const lean = 0.06;
    vertices.push(x - dx, 0, z - dz, 0, 1, 0, x + dx, 0, z + dz, 0, 1, 0, x + dz * 2 + lean * Math.cos(angle * 3), height * 0.26, z - dx * 2, 0, 1, 0);
    indices.push(base, base + 1, base + 2);
  }
  return plain(vertices, indices);
}

// Two flat sheets that cross: a column of light above the food.
export function beamMesh() {
  const vertices = [];
  const indices = [];
  for (const [dx, dz] of [[1, 0], [0, 1]]) {
    const base = vertices.length / 6;
    vertices.push(-dx, 0, -dz, 0, 1, 0, dx, 0, dz, 0, 1, 0, dx, 1, dz, 0, 1, 0, -dx, 1, -dz, 0, 1, 0);
    indices.push(base, base + 1, base + 2, base, base + 2, base + 3);
  }
  return plain(vertices, indices);
}

// ---------------------------------------------------------------------------
// The ground: two banks, the walls of the gap and the land around them.
//
// Each vertex has: position (3), normal (3) and color (3).

export const GAP_DEPTH = 3.4;

export function terrainMesh(grid, seed) {
  const noise = noiseFrom(seed);
  const pad = 26;
  const step = 0.5;
  const columns = Math.round((grid.width + 2 * pad) / step);
  const x0 = -pad;
  const nearEdgeRow = grid.nearRows - 1;
  const farEdgeRow = grid.nearRows + grid.gapRows;
  const tip = 1 / Math.sqrt(3);
  const zEnd = (grid.rows - 1) * ROW_STEP;

  // The edge of a bank follows the sides of the cells of its last row.
  const edge = (row, k, sign) => {
    const isTip = ((k - (row & 1)) & 1) === 0;
    return row * ROW_STEP + sign * (isTip ? tip : tip / 2);
  };

  const vertices = [];
  const indices = [];

  // The height and the color of the ground at a point.
  const height = (x, z) => {
    // Outside of the grid the ground goes up. The player sees where the world ends.
    const outside = Math.max(0, -x - 0.5, x - grid.width, -z - 0.5, z - zEnd - 0.5);
    const hills = Math.min(1, outside / 9);
    return (noise(x * 0.35, z * 0.35) - 0.5) * 0.05 + hills * hills * (0.6 + 2.2 * noise(x * 0.11 + 3, z * 0.11));
  };
  const color = (x, z, wall) => {
    const patch = noise(x * 0.23 + 40, z * 0.23 + 11);
    const fine = noise(x * 1.7, z * 1.7 + 30);
    const grass = [0.3 + 0.1 * fine, 0.47 + 0.1 * fine, 0.2 + 0.04 * fine];
    const dirt = [0.5, 0.4, 0.27];
    const rock = [0.42 - wall * 0.05, 0.37 - wall * 0.05, 0.33 - wall * 0.04];
    const d = Math.max(0, Math.min(1, (patch - 0.56) * 5));
    const mixed = [0, 1, 2].map((i) => grass[i] + (dirt[i] - grass[i]) * d);
    return [0, 1, 2].map((i) => mixed[i] + (rock[i] - mixed[i]) * wall);
  };

  const bank = (zFrom, edgeRow, sign) => {
    // `sign` is 1 for the near bank (the edge is at its high z) and -1 for the far bank.
    const depth = Math.abs(edgeRow * ROW_STEP + sign * tip - zFrom);
    const rows = Math.ceil(depth / step);
    const base = vertices.length / 9;
    const wallRows = 4;
    for (let j = 0; j <= rows + wallRows; j++) {
      for (let k = 0; k <= columns; k++) {
        const x = x0 + k * step;
        const zEdge = edge(edgeRow, Math.round(x / step), sign);
        let z;
        let y;
        let wall = 0;
        if (j <= rows) {
          // The top of the bank. The last line of vertices is on the edge.
          const flat = zFrom + sign * j * step;
          z = j === rows ? zEdge : sign * flat < sign * zEdge - 0.2 ? flat : zEdge - sign * 0.2;
          y = height(x, z);
          wall = Math.max(0, 1 - Math.abs(zEdge - z) / 0.45) * 0.55;
        } else {
          // The wall of the gap, with rough rock.
          const part = (j - rows) / wallRows;
          const rough = noise(x * 0.9 + 70, part * 3.1) - 0.5;
          z = zEdge + sign * (0.15 * part + rough * 0.35 * Math.sin(part * Math.PI));
          y = -GAP_DEPTH * 1.15 * part;
          wall = 1;
        }
        vertices.push(x, y, z, 0, 0, 0, ...color(x, z, wall));
      }
    }
    for (let j = 0; j < rows + wallRows; j++) {
      for (let k = 0; k < columns; k++) {
        const a = base + j * (columns + 1) + k;
        const b = a + columns + 1;
        if (sign > 0) indices.push(a, b, a + 1, a + 1, b, b + 1);
        else indices.push(a, a + 1, b, a + 1, b + 1, b);
      }
    }
  };

  bank(-pad, nearEdgeRow, 1);
  bank(zEnd + pad, farEdgeRow, -1);

  // The normals: the sum of the normals of the triangles at each vertex.
  for (let i = 0; i < indices.length; i += 3) {
    const [a, b, c] = [indices[i] * 9, indices[i + 1] * 9, indices[i + 2] * 9];
    const ux = vertices[b] - vertices[a];
    const uy = vertices[b + 1] - vertices[a + 1];
    const uz = vertices[b + 2] - vertices[a + 2];
    const vx = vertices[c] - vertices[a];
    const vy = vertices[c + 1] - vertices[a + 1];
    const vz = vertices[c + 2] - vertices[a + 2];
    const n = [uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx];
    for (const vertex of [a, b, c]) {
      vertices[vertex + 3] += n[0];
      vertices[vertex + 4] += n[1];
      vertices[vertex + 5] += n[2];
    }
  }
  for (let i = 0; i < vertices.length; i += 9) {
    const length = Math.hypot(vertices[i + 3], vertices[i + 4], vertices[i + 5]) || 1;
    vertices[i + 3] /= length;
    vertices[i + 4] /= length;
    vertices[i + 5] /= length;
  }

  return { vertices: new Float32Array(vertices), indices: new Uint32Array(indices), stride: 9, height, pad };
}
