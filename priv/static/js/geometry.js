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
// Each vertex has 13 numbers:
//   position (3) and normal (3) of a body that walks
//   weight (0 at the body, 1 at the foot), step group (0 or 1) and shade
//   position (3) of a body that is locked, and the number of the leg (-1 for the body)
//
// A locked body is flat and low. Each of its 6 legs goes in one of the 6 directions of
// the cells that it touches: to the body or to the bank that is there.

const VERTEX = 13;

function ellipsoid(out, center, radius, shade) {
  const segments = 8;
  const rings = 5;
  const base = out.vertices.length / VERTEX;
  for (let ring = 0; ring <= rings; ring++) {
    const v = (ring / rings) * Math.PI;
    for (let segment = 0; segment <= segments; segment++) {
      const u = (segment / segments) * 2 * Math.PI;
      const nx = Math.sin(v) * Math.cos(u);
      const ny = Math.cos(v);
      const nz = Math.sin(v) * Math.sin(u);
      // The normal of an ellipsoid: the direction divided by the radius.
      const length = Math.hypot(nx / radius[0], ny / radius[1], nz / radius[2]);
      const x = center[0] + nx * radius[0];
      const y = center[1] + ny * radius[1];
      const z = center[2] + nz * radius[2];
      out.vertices.push(
        x, y, z,
        nx / radius[0] / length, ny / radius[1] / length, nz / radius[2] / length,
        0, 0, shade,
        // Locked: wider, longer and half as high.
        x * 1.45, 0.03 + y * 0.5, z * 1.2, -1
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

// The 6 corners of one part of a leg: a thin bar with three sides, from a point to a point.
function barPoints(from, to, thickness) {
  const axis = [to[0] - from[0], to[1] - from[1], to[2] - from[2]];
  const length = Math.hypot(...axis);
  const a = axis.map((part) => part / length);
  // Two directions at a right angle to the bar.
  let u = Math.abs(a[1]) < 0.9 ? [a[2], 0, -a[0]] : [1, 0, 0];
  const uLength = Math.hypot(...u);
  u = u.map((part) => part / uLength);
  const v = [a[1] * u[2] - a[2] * u[1], a[2] * u[0] - a[0] * u[2], a[0] * u[1] - a[1] * u[0]];
  const points = [];
  for (const [point, size] of [[from, thickness], [to, thickness * 0.7]]) {
    for (let side = 0; side < 3; side++) {
      const angle = (side / 3) * 2 * Math.PI;
      const n = [0, 1, 2].map((i) => u[i] * Math.cos(angle) + v[i] * Math.sin(angle));
      points.push({ position: [point[0] + n[0] * size, point[1] + n[1] * size, point[2] + n[2] * size], normal: n });
    }
  }
  return points;
}

// One part of a leg, for a body that walks (`walk`) and for a locked body (`lock`).
function bar(out, walk, lock, weights, group, leg) {
  const base = out.vertices.length / VERTEX;
  const a = barPoints(walk[0], walk[1], walk[2]);
  const b = barPoints(lock[0], lock[1], lock[2]);
  for (let i = 0; i < 6; i++) {
    out.vertices.push(...a[i].position, ...a[i].normal, weights[i < 3 ? 0 : 1], group, 0.55, ...b[i].position, leg);
  }
  for (let side = 0; side < 3; side++) {
    const next = (side + 1) % 3;
    out.indices.push(base + side, base + 3 + side, base + next, base + next, base + 3 + side, base + 3 + next);
  }
}

// The direction to each of the 6 cells that touch a cell, as [x, z]. The numbers of the
// directions are the numbers of hex.js: 0 right, 1 left, 2 next row right, 3 next row
// left, 4 row before right, 5 row before left.
const DIRECTIONS = [[1, 0], [-1, 0], [0.5, ROW_STEP], [-0.5, ROW_STEP], [0.5, -ROW_STEP], [-0.5, -ROW_STEP]];

export function bodyMesh() {
  const out = { vertices: [], indices: [] };
  // The front of the body is in the +z direction. The feet are at y = 0.
  ellipsoid(out, [0, 0.13, -0.23], [0.125, 0.105, 0.2], 0.92);
  ellipsoid(out, [0, 0.12, 0.02], [0.075, 0.07, 0.115], 1.0);
  ellipsoid(out, [0, 0.135, 0.2], [0.09, 0.075, 0.09], 1.08);

  // hip, knee, foot of the three legs on one side, and the direction of each leg of a
  // locked body: the front legs go to the next row, the middle legs to the sides, the
  // back legs to the row before.
  const legs = [
    [[0.05, 0.11, 0.09], [0.17, 0.2, 0.19], [0.27, 0, 0.3], [2, 3]],
    [[0.06, 0.11, 0.02], [0.21, 0.21, 0.02], [0.33, 0, 0.0], [0, 1]],
    [[0.05, 0.11, -0.05], [0.18, 0.2, -0.16], [0.28, 0, -0.32], [4, 5]],
  ];
  legs.forEach(([hip, knee, foot, directions], index) => {
    for (const side of [1, -1]) {
      // Three legs move together: front and back of one side with the middle of the other side.
      const group = (index + (side > 0 ? 0 : 1)) % 2;
      const mirror = (point) => [point[0] * side, point[1], point[2]];
      const leg = directions[side > 0 ? 0 : 1];
      const [dx, dz] = DIRECTIONS[leg];
      // The leg of a locked body goes flat from the body to the edge of the cell, and a
      // small distance more: it gets to the leg of the body in the next cell.
      const at = (distance, y) => [dx * distance, y, dz * distance];
      bar(out, [mirror(hip), mirror(knee), 0.02], [at(0.06, 0.07), at(0.3, 0.1), 0.045], [0, 0.5], group, leg);
      bar(out, [mirror(knee), mirror(foot), 0.016], [at(0.3, 0.1), at(0.54, 0.05), 0.04], [0.5, 1], group, leg);
    }
  });
  return { vertices: new Float32Array(out.vertices), indices: new Uint16Array(out.indices), stride: VERTEX };
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
// The ground: two banks, the walls of the river and the land around them.
//
// Each bank cell is one hexagon, thus the edge of the ground is exactly the edge of the
// cells where a body can be. Each vertex has: position (3), normal (3) and color (3).

export const GAP_DEPTH = 3.4;

// Columns and rows of land around the grid. The fog hides the end of this land.
const LAND_COLUMNS = 20;
const LAND_ROWS_BEFORE = 16;
const LAND_ROWS_AFTER = 12;

export function terrainMesh(grid, seed) {
  const noise = noiseFrom(seed);
  const size = 1 / Math.sqrt(3);
  const zEnd = (grid.rows - 1) * ROW_STEP;

  // The width of the river in a column. Outside of the grid, the river continues with
  // the width of the first or the last column.
  const river = (col) => grid.river[Math.max(0, Math.min(grid.width - 1, col))];
  const isBank = (row, col) => row < grid.nearRows || row >= grid.nearRows + river(col);

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
  // The normal of the ground at a point, from the height near it.
  const normal = (x, z) => {
    const e = 0.2;
    const n = [height(x - e, z) - height(x + e, z), 2 * e, height(x, z - e) - height(x, z + e)];
    const length = Math.hypot(...n);
    return n.map((part) => part / length);
  };

  const vertices = [];
  const indices = [];
  const push = (x, y, z, n, c) => {
    vertices.push(x, y, z, n[0], n[1], n[2], c[0], c[1], c[2]);
    return vertices.length / 9 - 1;
  };

  // The cell that touches the side `i` of a cell: the side from corner i to corner i + 1.
  // Corner i is at the angle 30 + 60 * i degrees.
  const beside = (row, col, i) => {
    const shift = row & 1;
    return [
      [row + 1, col + shift], [row + 1, col + shift - 1], [row, col - 1],
      [row - 1, col + shift - 1], [row - 1, col + shift], [row, col + 1],
    ][i];
  };

  for (let row = -LAND_ROWS_BEFORE; row < grid.rows + LAND_ROWS_AFTER; row++) {
    for (let col = -LAND_COLUMNS; col < grid.width + LAND_COLUMNS; col++) {
      if (!isBank(row, col)) continue;
      const cx = col + 0.5 * (row & 1);
      const cz = row * ROW_STEP;
      const corners = [];
      const walls = [];
      for (let i = 0; i < 6; i++) {
        const [r, c] = beside(row, col, i);
        walls.push(!isBank(r, c));
      }
      for (let i = 0; i < 6; i++) {
        const angle = ((30 + 60 * i) * Math.PI) / 180;
        const x = cx + Math.cos(angle) * size;
        const z = cz + Math.sin(angle) * size;
        // The ground near the river is rock.
        const edge = walls[i] || walls[(i + 5) % 6] ? 0.55 : 0;
        corners.push({ x, z, y: height(x, z), index: push(x, height(x, z), z, normal(x, z), color(x, z, edge)) });
      }
      const rim = walls.some(Boolean) ? 0.25 : 0;
      const center = push(cx, height(cx, cz), cz, normal(cx, cz), color(cx, cz, rim));
      for (let i = 0; i < 6; i++) indices.push(center, corners[(i + 1) % 6].index, corners[i].index);

      // The wall of the river below each side that touches the river, with rough rock.
      for (let i = 0; i < 6; i++) {
        if (!walls[i]) continue;
        const a = corners[i];
        const b = corners[(i + 1) % 6];
        const out = [(a.x + b.x) / 2 - cx, (a.z + b.z) / 2 - cz];
        const length = Math.hypot(...out);
        const n = [out[0] / length, 0.25, out[1] / length];
        const parts = 3;
        let before = null;
        for (let part = 0; part <= parts; part++) {
          const t = part / parts;
          const line = [a, b].map((corner) => {
            const rough = (noise(corner.x * 0.9 + 70, corner.z * 0.9 + t * 3.1) - 0.5) * 0.3 * Math.sin(t * Math.PI);
            const x = corner.x + n[0] * (0.16 * t + rough);
            const z = corner.z + n[2] * (0.16 * t + rough);
            return push(x, corner.y - (corner.y + GAP_DEPTH * 1.15) * t, z, n, color(x, z, 1));
          });
          if (before) indices.push(before[0], before[1], line[0], before[1], line[1], line[0]);
          before = line;
        }
      }
    }
  }

  return {
    vertices: new Float32Array(vertices),
    indices: new Uint32Array(indices),
    stride: 9,
    height,
    isBank,
    columns: LAND_COLUMNS,
    rowsBefore: LAND_ROWS_BEFORE,
    rowsAfter: LAND_ROWS_AFTER,
  };
}
