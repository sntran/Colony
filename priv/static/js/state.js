// The world as the page knows it.
//
// The server sends a snapshot, then the changes of each tick. This file reads them and
// keeps the positions that the page draws. lib/colony/protocol.ex tells the format.

import { Grid, GAP } from "./hex.js";
import { colorOf, WORKER_COLOR, HELPER_COLOR } from "./names.js";

const MAX_WORKERS = 8192;

// Floats for each body in the list that the renderer gets:
// x, y, z, scale; cos and sin of the heading, 0, 0;
// red, green, blue, lock; sin and cos of the walk phase, legs, shake.
// `legs` has one bit for each leg of a locked body: the leg goes out if a body or a bank
// is in that direction.
export const BODY_STRIDE = 16;
// Floats for each plain shape: x, y, z, turn, scale x, scale y, scale z, red, green, blue, alpha.
export const MESH_STRIDE = 11;

// A free body on a locked body is this much above the ground.
const BRIDGE_HEIGHT = 0.1;
const FOOD_COLOR = [1.0, 0.74, 0.2];

function hash01(value) {
  let x = Math.imul(value ^ 0x9e3779b9, 0x85ebca6b);
  x ^= x >>> 13;
  x = Math.imul(x, 0xc2b2ae35);
  x ^= x >>> 16;
  return (x >>> 0) / 4294967296;
}

function turnToward(from, to, amount) {
  let difference = to - from;
  while (difference > Math.PI) difference -= 2 * Math.PI;
  while (difference < -Math.PI) difference += 2 * Math.PI;
  return from + difference * Math.min(1, amount);
}

// The color of a locked body: the color of its player, darker. A bridge is a structure,
// and the free bodies on it must be easy to see.
function lockedColor(color) {
  return [color[0] * 0.62 + 0.03, color[1] * 0.62 + 0.03, color[2] * 0.62 + 0.03];
}

export class World {
  constructor() {
    this.ready = false;
    this.pending = [];
    this.grid = null;
    this.tick = 0;
    this.you = 0xffff;
    this.speed = 4;
    this.rate = 10;
    this.decayTicks = 10;
    this.pileUnits = 300;
    // The numbers of the support rule: see support.js.
    this.rule = { bank: 96, costs: [12, 6, 4, 3] };

    this.workers = {
      alive: new Uint8Array(MAX_WORKERS),
      cell: new Uint16Array(MAX_WORKERS),
      carry: new Uint8Array(MAX_WORKERS),
      x: new Float32Array(MAX_WORKERS),
      y: new Float32Array(MAX_WORKERS),
      z: new Float32Array(MAX_WORKERS),
      heading: new Float32Array(MAX_WORKERS),
      phase: new Float32Array(MAX_WORKERS),
    };
    this.workerEnd = 0;
    this.freeWorkers = 0;

    this.players = new Map();
    // id => { name, helper }
    this.names = new Map();
    // cell => locked body
    this.locked = new Map();
    this.lockInfo = new Map();
    // This number changes each time the locked bodies change.
    this.structure = 0;
    this.scent = new Uint8Array(0);
    this.scentDirty = true;
    this.pile = { id: 0, cell: 0, units: 0 };
    this.foodNest = 0;
    this.foodDirty = true;
    this.time = 0;

    // The body of this player. The page moves it; the server checks the moves.
    // `slide` is the distance from the place where the picture of the body is to the
    // place where the body is: after a lock, the picture goes smoothly to the new body.
    this.me = { alive: false, x: 0, y: 0, z: 0, heading: 0, phase: 0, scent: false, name: "", color: [1, 1, 1], slideX: 0, slideZ: 0 };

    this.bodies = new Float32Array(BODY_STRIDE * 4096);
    this.bodyCount = 0;
    this.shadows = new Float32Array(MESH_STRIDE * 4096);
    this.shadowCount = 0;
    this.crumbs = new Float32Array(MESH_STRIDE * 4096);
    this.crumbCount = 0;
    this.decks = new Float32Array(MESH_STRIDE * 1024);
    this.deckCount = 0;
  }

  // ---------------------------------------------------------------------------
  // Messages

  snapshot(buffer) {
    this.reset();
    this.read(buffer, true);
    this.ready = true;
    const pending = this.pending;
    this.pending = [];
    for (const tick of pending) {
      if (new DataView(tick).getUint32(0, true) > this.tick) this.read(tick, false);
    }
  }

  applyTick(buffer) {
    // A tick can come before the snapshot. Keep it for later.
    if (!this.ready) {
      this.pending.push(buffer);
      return;
    }
    if (new DataView(buffer).getUint32(0, true) > this.tick) this.read(buffer, false);
  }

  reset() {
    this.workers.alive.fill(0);
    this.workerEnd = 0;
    this.players.clear();
    this.names.clear();
    this.locked.clear();
    this.lockInfo.clear();
    this.structure++;
    this.scent.fill(0);
    this.scentDirty = true;
    this.foodDirty = true;
  }

  read(buffer, snapshot) {
    const view = new DataView(buffer);
    const text = new TextDecoder();
    const w = this.workers;
    let o = 4;
    this.tick = view.getUint32(0, true);

    if (!snapshot) {
      // The server subtracts 1 from each scent at these ticks. The page does the same.
      if (this.tick % this.decayTicks === 0) {
        const scent = this.scent;
        for (let i = 0; i < scent.length; i++) if (scent[i] > 0) scent[i]--;
        this.scentDirty = true;
      }
      for (const player of this.players.values()) player.seen = false;
    }

    while (o < view.byteLength) {
      const tag = view.getUint8(o);
      const count = view.getUint16(o + 1, true);
      o += 3;

      switch (tag) {
        case 1: {
          const width = view.getUint16(o, true);
          const nearRows = view.getUint8(o + 2);
          const rows = view.getUint8(o + 3);
          this.nest = view.getUint16(o + 4, true);
          this.seed = view.getUint32(o + 6, true);
          this.you = view.getUint16(o + 10, true);
          this.rate = view.getUint8(o + 12);
          this.speed = view.getUint8(o + 13) / 10;
          this.decayTicks = view.getUint16(o + 14, true);
          this.pileUnits = view.getUint16(o + 16, true);
          const bank = view.getUint8(o + 18);
          const costCount = view.getUint8(o + 19);
          o += 20;
          const costs = [];
          for (let i = 0; i < costCount; i++) costs.push(view.getUint8(o + i));
          o += costCount;
          this.rule = { bank, costs };
          const river = new Uint8Array(buffer.slice(o, o + width));
          o += width;
          this.grid = new Grid(width, nearRows, rows, river);
          if (this.scent.length !== this.grid.count) this.scent = new Uint8Array(this.grid.count);
          break;
        }
        case 2:
          for (let i = 0; i < count; i++) {
            const id = view.getUint16(o, true);
            const helper = view.getUint8(o + 2) === 1;
            const size = view.getUint8(o + 3);
            this.names.set(id, { name: text.decode(new Uint8Array(buffer, o + 4, size)), helper });
            o += 4 + size;
          }
          break;
        case 3:
          for (let i = 0; i < count; i++) {
            this.setWorker(view.getUint16(o, true), view.getUint16(o + 2, true), view.getUint8(o + 4));
            o += 5;
          }
          break;
        case 4:
          for (let i = 0; i < count; i++) {
            const value = view.getUint16(o, true);
            const id = value >> 3;
            if (w.alive[id]) {
              const to = this.grid.neighbor(w.cell[id], value & 7);
              if (to >= 0) w.cell[id] = to;
            }
            o += 2;
          }
          break;
        case 5:
          for (let i = 0; i < count; i++) {
            w.alive[view.getUint16(o, true)] = 0;
            o += 2;
          }
          break;
        case 6:
          for (let i = 0; i < count; i++) {
            const cell = view.getUint16(o, true);
            const helper = view.getUint8(o + 2) === 2;
            const id = view.getUint16(o + 3, true);
            const time = view.getUint32(o + 5, true);
            const size = view.getUint8(o + 9);
            const name = text.decode(new Uint8Array(buffer, o + 10, size));
            o += 10 + size;
            this.lockInfo.set(cell, { helper, time, name, from: snapshot ? null : this.lockStart(id) });
          }
          break;
        case 8: {
          const locked = new Map();
          for (let i = 0; i < count; i++) {
            const cell = view.getUint16(o, true);
            let body = this.locked.get(cell);
            if (!body) body = this.newLocked(cell);
            body.support = view.getUint8(o + 2);
            locked.set(cell, body);
            o += 3;
          }
          this.locked = locked;
          this.structure++;
          for (const cell of this.lockInfo.keys()) if (!locked.has(cell)) this.lockInfo.delete(cell);
          break;
        }
        case 10:
          for (let i = 0; i < count; i++) {
            this.scent[view.getUint16(o, true)] = view.getUint8(o + 2);
            o += 3;
          }
          this.scentDirty = true;
          break;
        case 11:
          this.pile = { id: view.getUint16(o, true), cell: view.getUint16(o + 2, true), units: view.getUint16(o + 4, true) };
          this.foodNest = view.getUint32(o + 6, true);
          this.foodDirty = true;
          o += 10 * count;
          break;
        case 12:
          for (let i = 0; i < count; i++) {
            const id = view.getUint16(o, true);
            const x = view.getUint16(o + 2, true) / 1000 - 1;
            const z = view.getUint16(o + 4, true) / 1000 - 1;
            const heading = (view.getUint8(o + 6) / 256) * 2 * Math.PI;
            let player = this.players.get(id);
            if (!player) {
              player = { x, y: 0, z, heading, phase: 0 };
              this.players.set(id, player);
            }
            const known = this.names.get(id) || { name: "", helper: false };
            player.tx = x;
            player.tz = z;
            player.theading = heading;
            player.scent = view.getUint8(o + 7) === 1;
            player.seen = true;
            player.name = known.name;
            player.helper = known.helper;
            player.color = known.helper ? HELPER_COLOR : colorOf(known.name);
            o += 8;
          }
          break;
        default:
          // A section that this page does not know. The page cannot continue with this message.
          return;
      }
    }

    for (const [id, player] of this.players) if (!player.seen) this.players.delete(id);
  }

  setWorker(id, cell, flags) {
    const w = this.workers;
    const grid = this.grid;
    const wasAlive = w.alive[id] === 1;
    const jump = (flags & 2) !== 0;
    if (!wasAlive || jump) {
      w.x[id] = grid.x(cell) + this.offsetX(id, cell);
      w.z[id] = grid.z(cell) + this.offsetZ(id, cell);
      w.y[id] = grid.kind(cell) === GAP ? BRIDGE_HEIGHT : 0;
      w.heading[id] = hash01(id * 7 + this.tick) * 2 * Math.PI;
      w.phase[id] = hash01(id) * 6;
    }
    w.alive[id] = 1;
    w.cell[id] = cell;
    w.carry[id] = flags & 1;
    if (id >= this.workerEnd) this.workerEnd = id + 1;
  }

  // The player takes the body of a worker. Returns the place where the picture of that
  // worker is, or null. The worker is not a worker after that.
  takeWorker(id) {
    const w = this.workers;
    if (id === null || id === undefined || !w.alive[id]) return null;
    w.alive[id] = 0;
    return [w.x[id], w.z[id], w.heading[id]];
  }

  // The position where a body was before its lock.
  lockStart(id) {
    if (id === this.you) return [this.me.x + this.me.slideX, this.me.z + this.me.slideZ];
    const player = this.players.get(id);
    return player ? [player.x, player.z] : null;
  }

  newLocked(cell) {
    const info = this.lockInfo.get(cell) || { helper: false, time: 0, name: "", from: null };
    return {
      cell,
      x: this.grid.x(cell),
      z: this.grid.z(cell),
      support: 0,
      helper: info.helper,
      name: info.name,
      time: info.time,
      color: lockedColor(info.helper ? HELPER_COLOR : colorOf(info.name)),
      from: info.from,
      start: this.time,
    };
  }

  // Each worker is a small distance from the center of its cell. A line of workers
  // then does not look like one body.
  offsetX(id, cell) {
    return (hash01(id * 2 + 1) - 0.5) * (this.grid.kind(cell) === GAP ? 0.3 : 0.5);
  }

  offsetZ(id, cell) {
    return (hash01(id * 2 + 2) - 0.5) * (this.grid.kind(cell) === GAP ? 0.3 : 0.42);
  }

  // True if a free body can be on the point.
  canStand(x, z) {
    const cell = this.grid.cellAt(x, z);
    return cell >= 0 && (this.grid.kind(cell) !== GAP || this.locked.has(cell));
  }

  // The height of a free body at a point.
  heightAt(x, z) {
    const cell = this.grid.cellAt(x, z);
    return cell >= 0 && this.grid.kind(cell) === GAP ? BRIDGE_HEIGHT : 0;
  }

  // ---------------------------------------------------------------------------
  // Each frame

  // Moves the drawn bodies in the direction of their positions on the server.
  update(dt) {
    this.time += dt;
    const grid = this.grid;
    const w = this.workers;
    const speed = this.speed;
    let free = 0;

    for (let id = 0; id < this.workerEnd; id++) {
      if (!w.alive[id]) continue;
      free++;
      const cell = w.cell[id];
      const dx = grid.x(cell) + this.offsetX(id, cell) - w.x[id];
      const dz = grid.z(cell) + this.offsetZ(id, cell) - w.z[id];
      const distance = Math.hypot(dx, dz);
      if (distance > 8) {
        w.x[id] += dx;
        w.z[id] += dz;
      } else if (distance > 0.02) {
        // A worker that is behind goes faster.
        const step = Math.min(distance, speed * Math.max(1, distance / 1.1) * dt);
        w.x[id] += (dx / distance) * step;
        w.z[id] += (dz / distance) * step;
        w.heading[id] = turnToward(w.heading[id], Math.atan2(dx, dz), dt * 14);
        w.phase[id] += step * 13;
      }
      const height = this.heightAt(w.x[id], w.z[id]);
      w.y[id] += (height - w.y[id]) * Math.min(1, dt * 12);
    }
    this.freeWorkers = free;

    for (const [id, player] of this.players) {
      if (id === this.you) continue;
      const dx = player.tx - player.x;
      const dz = player.tz - player.z;
      const distance = Math.hypot(dx, dz);
      if (distance > 6) {
        player.x = player.tx;
        player.z = player.tz;
      } else if (distance > 0.005) {
        const step = Math.min(distance, Math.max(speed, distance * 8) * dt);
        player.x += (dx / distance) * step;
        player.z += (dz / distance) * step;
        player.phase += step * 13;
      }
      player.heading = turnToward(player.heading, player.theading, dt * 12);
      player.y += (this.heightAt(player.x, player.z) - player.y) * Math.min(1, dt * 12);
    }

    // The picture of the body of this player goes to the place of its new body.
    const fade = Math.exp(-dt * 9);
    this.me.slideX *= fade;
    this.me.slideZ *= fade;
  }

  // The bits of the legs of a locked body: one for each direction that has a locked body
  // or a bank. Its legs go out in these directions.
  legs(cell) {
    const grid = this.grid;
    let bits = 0;
    for (let direction = 0; direction < 6; direction++) {
      const next = grid.neighbor(cell, direction);
      if (next >= 0 && (grid.kind(next) !== GAP || this.locked.has(next))) bits |= 1 << direction;
    }
    return bits;
  }

  // Makes the lists that the renderer draws. `sees(x, z)` tells if a point is in the picture.
  build(sees) {
    const w = this.workers;
    let b = 0;
    let s = 0;
    let c = 0;
    let d = 0;
    const need = this.workerEnd + this.players.size + this.locked.size + 2;
    if (need * BODY_STRIDE > this.bodies.length) {
      this.bodies = new Float32Array(need * BODY_STRIDE * 2);
      this.shadows = new Float32Array(need * MESH_STRIDE * 2);
      this.crumbs = new Float32Array(need * MESH_STRIDE * 2);
    }
    if (this.locked.size * MESH_STRIDE > this.decks.length) {
      this.decks = new Float32Array(this.locked.size * MESH_STRIDE * 2);
    }
    const bodies = this.bodies;
    const shadows = this.shadows;
    const crumbs = this.crumbs;
    const decks = this.decks;
    const time = this.time;

    const body = (x, y, z, heading, color, phase, lock, strain, scale, legs) => {
      bodies[b++] = x; bodies[b++] = y; bodies[b++] = z; bodies[b++] = scale;
      bodies[b++] = Math.cos(heading); bodies[b++] = Math.sin(heading); bodies[b++] = 1; bodies[b++] = 0;
      if (strain > 0) {
        // A body with not much support goes red and back, again and again.
        const alarm = strain * (0.3 + 0.2 * (1 + Math.sin(time * 7)));
        bodies[b++] = color[0] + (1 - color[0]) * alarm;
        bodies[b++] = color[1] + (0.12 - color[1]) * alarm;
        bodies[b++] = color[2] + (0.08 - color[2]) * alarm;
      } else {
        bodies[b++] = color[0]; bodies[b++] = color[1]; bodies[b++] = color[2];
      }
      bodies[b++] = lock;
      bodies[b++] = lock === 1 ? 0 : Math.sin(phase); bodies[b++] = lock === 1 ? 1 : Math.cos(phase);
      bodies[b++] = legs;
      bodies[b++] = strain > 0 ? Math.sin(time * 37 + x * 5 + z * 3) * 0.014 * strain : 0;
    };
    // The shadow of a free body: on the ground, or on the bodies of a bridge.
    const shadow = (x, y, z, size) => {
      shadows[s++] = x; shadows[s++] = y + 0.012; shadows[s++] = z; shadows[s++] = 0;
      shadows[s++] = size; shadows[s++] = 1; shadows[s++] = size;
      shadows[s++] = 0; shadows[s++] = 0; shadows[s++] = 0; shadows[s++] = y > 0.03 ? 0.4 : 0.26;
    };

    for (let id = 0; id < this.workerEnd; id++) {
      if (!w.alive[id] || !sees(w.x[id], w.z[id])) continue;
      const heading = w.heading[id];
      body(w.x[id], w.y[id], w.z[id], heading, WORKER_COLOR, w.phase[id], 0, 0, 1, 0);
      shadow(w.x[id], w.y[id], w.z[id], 0.3);
      if (w.carry[id]) {
        crumbs[c++] = w.x[id] + Math.sin(heading) * 0.3; crumbs[c++] = w.y[id] + 0.2; crumbs[c++] = w.z[id] + Math.cos(heading) * 0.3; crumbs[c++] = id;
        crumbs[c++] = 0.1; crumbs[c++] = 0.1; crumbs[c++] = 0.1;
        crumbs[c++] = FOOD_COLOR[0]; crumbs[c++] = FOOD_COLOR[1]; crumbs[c++] = FOOD_COLOR[2]; crumbs[c++] = 1;
      }
    }

    for (const [id, player] of this.players) {
      if (id === this.you) continue;
      body(player.x, player.y, player.z, player.heading, player.color, player.phase, 0, 0, 1.12, 0);
      shadow(player.x, player.y, player.z, 0.34);
    }

    const me = this.me;
    if (me.alive) {
      body(me.x + me.slideX, me.y, me.z + me.slideZ, me.heading, me.color, me.phase, 0, 0, 1.12, 0);
      shadow(me.x + me.slideX, me.y, me.z + me.slideZ, 0.34);
    }

    // The lowest cost of the rule: a body with less support than 2 rows of this is weak.
    const row = this.rule.costs[0];
    for (const locked of this.locked.values()) {
      if (!sees(locked.x, locked.z)) continue;
      // A new locked body moves from the place of its free body into its cell.
      let x = locked.x;
      let z = locked.z;
      const age = (this.time - locked.start) / 0.22;
      if (locked.from && age < 1) {
        const part = age * age * (3 - 2 * age);
        x = locked.from[0] + (x - locked.from[0]) * part;
        z = locked.from[1] + (z - locked.from[1]) * part;
      }
      const strain = Math.max(0, Math.min(1, (row - locked.support) / row + 0.4)) * (locked.support <= row ? 1 : 0);
      // All the locked bodies look to the far bank: each leg then has one direction.
      body(x, -0.02, z, 0, locked.color, 0, 1, strain, 1.0, this.legs(locked.cell));
      // A dark plate below the body: the bridge is one structure.
      decks[d++] = locked.x; decks[d++] = -0.03; decks[d++] = locked.z; decks[d++] = 0;
      decks[d++] = 1.12; decks[d++] = 1; decks[d++] = 1.12;
      decks[d++] = 0.05; decks[d++] = 0.04; decks[d++] = 0.035; decks[d++] = 0.55;
    }

    this.bodyCount = b / BODY_STRIDE;
    this.shadowCount = s / MESH_STRIDE;
    this.crumbCount = c / MESH_STRIDE;
    this.deckCount = d / MESH_STRIDE;
  }

  // The number of bodies in the world: free workers, players and locked bodies.
  bodyTotal() {
    return this.freeWorkers + this.players.size + this.locked.size;
  }
}

export { FOOD_COLOR, hash01 };
