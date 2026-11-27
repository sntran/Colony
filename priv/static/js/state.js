// The world as the page knows it.
//
// The server sends a snapshot, then the changes of each tick. This file reads them and
// keeps the positions that the page draws. lib/colony/protocol.ex tells the format.

import { Grid, GAP, LAND } from "./hex.js";
import { colorOf, SPARE_COLOR, CARRIER_COLOR, HELPER_COLOR } from "./names.js";

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
const EGG_COLOR = [0.97, 0.96, 0.9];
// A carrier is smaller and darker than a spare body. A spare body is the size of the body
// of a player.
const CARRIER_SCALE = 0.78;
const SPARE_SCALE = 1.12;

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
    // The time of the first tick of the world, in seconds.
    this.startTime = 0;
    // The numbers of the support rule.
    this.rule = { bank: 96, costs: [12, 6, 4, 3] };

    this.workers = {
      alive: new Uint8Array(MAX_WORKERS),
      cell: new Uint32Array(MAX_WORKERS),
      // 0: no load, 1: food, 2: an egg.
      carry: new Uint8Array(MAX_WORKERS),
      // 1 for a carrier, 0 for a spare body.
      carrier: new Uint8Array(MAX_WORKERS),
      x: new Float32Array(MAX_WORKERS),
      y: new Float32Array(MAX_WORKERS),
      z: new Float32Array(MAX_WORKERS),
      heading: new Float32Array(MAX_WORKERS),
      phase: new Float32Array(MAX_WORKERS),
      // The time that the worker did not move.
      still: new Float32Array(MAX_WORKERS),
    };
    this.workerEnd = 0;
    // The spare bodies and the carriers. A lock uses a spare body.
    this.spare = 0;
    this.carriers = 0;
    // The person of this player: the server knows the person by the secret number.
    this.person = 0;

    this.players = new Map();
    // id => { name, helper }
    this.names = new Map();
    // cell => locked body
    this.locked = new Map();
    this.lockInfo = new Map();
    // This number changes each time the locked bodies or the open cells change.
    this.structure = 0;
    // The open cells: cell => gain. A lock is possible there, and it helps. In the
    // "wider" phase, the gain tells how much a body there helps.
    this.open = new Map();
    this.openBest = 0;
    // The nest and the nests before it: { cell, land }.
    this.nest = 0;
    this.oldNests = [];
    this.nestKey = 0;
    this.scent = new Uint8Array(0);
    this.scentDirty = true;
    // The piles of food: id => { id, cell, units, size, far, changed }. `far` is true
    // while no body can walk to the pile. `changed` is the time of the last loss.
    this.piles = new Map();
    // This number changes each time a pile appears, gets empty, or gets a way to it.
    this.pilesKey = "";
    this.foodNest = 0;
    // The river that the colony builds a bridge across now.
    this.stage = 1;
    this.complete = false;
    this.foodDirty = true;
    this.time = 0;
    // Things that occurred in the last messages. The page makes sounds and marks from
    // them, then it removes them: locks, new workers, and units of food at the nest.
    this.news = { locks: [], workers: 0, food: 0, nest: false };
    // The story shows only the locked bodies with a number of this or less, and it can
    // hide the free bodies.
    this.storyLimit = Infinity;
    this.hideFree = false;

    // The body of this player. The page moves it; the server checks the moves.
    // `slide` is the distance from the place where the picture of the body is to the
    // place where the body is: after a lock, the picture goes smoothly to the new body.
    // `arrive` is the time when the light of a lock gets to the new body: before that
    // time, the body has the color of a worker.
    this.me = { alive: false, x: 0, y: 0, z: 0, heading: 0, phase: 0, carry: false, name: "", color: [1, 1, 1], slideX: 0, slideZ: 0, arrive: -10 };

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
    this.open = new Map();
    this.openBest = 0;
    this.piles.clear();
    this.structure++;
    this.scent.fill(0);
    this.scentDirty = true;
    this.foodDirty = true;
  }

  read(buffer, snapshot) {
    this.inSnapshot = snapshot;
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
          const rows = view.getUint16(o + 2, true);
          this.seed = view.getUint32(o + 4, true);
          this.you = view.getUint16(o + 8, true);
          this.person = view.getUint16(o + 10, true);
          this.rate = view.getUint8(o + 12);
          this.speed = view.getUint8(o + 13) / 10;
          this.decayTicks = view.getUint16(o + 14, true);
          this.startTime = view.getUint32(o + 16, true);
          const bank = view.getUint8(o + 20);
          const costCount = view.getUint8(o + 21);
          o += 22;
          const costs = [];
          for (let i = 0; i < costCount; i++) costs.push(view.getUint8(o + i));
          o += costCount;
          this.rule = { bank, costs };
          const riverCount = view.getUint16(o, true);
          o += 2;
          const rivers = [];
          for (let k = 0; k < riverCount; k++) {
            rivers.push({ start: view.getUint16(o, true), widths: new Uint8Array(buffer.slice(o + 2, o + 2 + width)) });
            o += 2 + width;
          }
          this.grid = new Grid(width, rows, rivers);
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
            const flags = view.getUint8(o + 6);
            // A worker at a new position in a tick: the nest made it.
            if (!snapshot && flags & 2) this.news.workers++;
            this.setWorker(view.getUint16(o, true), view.getUint32(o + 2, true), flags);
            o += 7;
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
            const cell = view.getUint32(o, true);
            const helper = view.getUint8(o + 4) === 2;
            const id = view.getUint16(o + 5, true);
            const owner = view.getUint16(o + 7, true);
            const time = view.getUint32(o + 9, true);
            const n = view.getUint32(o + 13, true);
            const size = view.getUint8(o + 17);
            const name = text.decode(new Uint8Array(buffer, o + 18, size));
            o += 18 + size;
            this.lockInfo.set(cell, { helper, owner, time, name, n, from: snapshot ? null : this.lockStart(id) });
            if (!snapshot) {
              this.news.locks.push({ cell, id, name, helper, n });
              // The player has a different body now: its picture does not walk there.
              const player = this.players.get(id);
              if (player) player.jump = true;
            }
          }
          break;
        case 7:
          // A person has a new name: all the bodies of the person get it.
          for (let i = 0; i < count; i++) {
            const person = view.getUint16(o, true);
            const size = view.getUint8(o + 2);
            const name = text.decode(new Uint8Array(buffer, o + 3, size));
            o += 3 + size;
            for (const body of this.locked.values()) {
              if (body.owner === person && !body.helper) {
                body.name = name;
                body.color = lockedColor(colorOf(name));
              }
            }
            for (const info of this.lockInfo.values()) if (info.owner === person && !info.helper) info.name = name;
            this.news.renamed = true;
          }
          break;
        case 8: {
          // In the snapshot: all the locked bodies. In a tick: the bodies whose support
          // changed. No step removes a locked body.
          for (let i = 0; i < count; i++) {
            const cell = view.getUint32(o, true);
            let body = this.locked.get(cell);
            if (!body) {
              body = this.newLocked(cell);
              this.locked.set(cell, body);
            }
            body.support = view.getUint8(o + 4);
            o += 5;
          }
          this.structure++;
          break;
        }
        case 9: {
          const open = new Map();
          let best = 0;
          for (let i = 0; i < count; i++) {
            const gain = view.getUint8(o + 4);
            open.set(view.getUint32(o, true), gain);
            best = Math.max(best, gain);
            o += 5;
          }
          this.open = open;
          this.openBest = best;
          this.structure++;
          break;
        }
        case 10:
          for (let i = 0; i < count; i++) {
            this.scent[view.getUint32(o, true)] = view.getUint8(o + 4);
            o += 5;
          }
          this.scentDirty = true;
          break;
        case 11: {
          const food = view.getUint32(o, true);
          if (!snapshot && food > this.foodNest) this.news.food += food - this.foodNest;
          this.foodNest = food;
          this.stage = view.getUint16(o + 4, true);
          this.complete = view.getUint8(o + 6) === 1;
          this.foodDirty = true;
          o += 7 * count;
          break;
        }
        case 12:
          for (let i = 0; i < count; i++) {
            const id = view.getUint16(o, true);
            const x = view.getUint16(o + 2, true) / 500 - 1;
            const z = view.getUint32(o + 4, true) / 500 - 1;
            const heading = (view.getUint8(o + 8) / 256) * 2 * Math.PI;
            let player = this.players.get(id);
            if (!player) {
              player = { x, y: 0, z, heading, phase: 0 };
              this.players.set(id, player);
            }
            const known = this.names.get(id) || { name: "", helper: false };
            player.tx = x;
            player.tz = z;
            player.theading = heading;
            player.carry = view.getUint8(o + 9) === 1;
            player.seen = true;
            player.name = known.name;
            player.helper = known.helper;
            player.color = known.helper ? HELPER_COLOR : colorOf(known.name);
            if (id === this.you) this.me.carry = player.carry;
            o += 10;
          }
          break;
        case 13: {
          // In the snapshot: all the piles. In a tick: the piles that changed.
          for (let i = 0; i < count; i++) {
            const id = view.getUint16(o, true);
            const before = this.piles.get(id);
            const pile = {
              id,
              cell: view.getUint32(o + 2, true),
              units: view.getUint16(o + 6, true),
              size: view.getUint16(o + 8, true),
              least: view.getUint16(o + 10, true),
              far: view.getUint8(o + 12) === 1,
            };
            // The time when the page saw the pile first. A pile of the snapshot was
            // there before.
            pile.born = before ? before.born : snapshot ? -100 : this.time;
            // The time of the last unit that the pile lost while no body can walk to it.
            pile.changed = before ? before.changed : -100;
            if (before && pile.far && pile.units < before.units) pile.changed = this.time;
            this.piles.set(id, pile);
            o += 13;
          }
          let key = "";
          for (const pile of this.piles.values()) key += `${pile.id}${pile.far ? "f" : pile.units > 0 ? "u" : "e"}`;
          this.pilesKey = key;
          this.foodDirty = true;
          break;
        }
        case 14: {
          const nest = view.getUint32(o, true);
          const old = view.getUint16(o + 4, true);
          o += 6;
          const nests = [];
          for (let i = 0; i < old; i++) {
            nests.push({ cell: view.getUint32(o, true), land: view.getUint16(o + 4, true) });
            o += 6;
          }
          if (!snapshot && nest !== this.nest) this.news.nest = { from: this.nest, to: nest };
          this.nest = nest;
          this.oldNests = nests;
          this.nestKey++;
          this.foodDirty = true;
          break;
        }
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
    w.carry[id] = flags & 1 ? 1 : flags & 4 ? 2 : 0;
    w.carrier[id] = flags & 8 ? 1 : 0;
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
    const info = this.lockInfo.get(cell) || { helper: false, owner: 0, time: 0, name: "", n: 0, from: null };
    this.lockInfo.delete(cell);
    return {
      cell,
      n: info.n,
      owner: info.owner,
      river: this.grid.river(cell),
      row: this.grid.riverRow(cell),
      x: this.grid.x(cell),
      z: this.grid.z(cell),
      support: 0,
      helper: info.helper,
      name: info.name,
      time: info.time,
      color: lockedColor(info.helper ? HELPER_COLOR : colorOf(info.name)),
      from: info.from,
      // The time of the lock on the page. A body of the snapshot locked before.
      start: this.inSnapshot ? -100 : this.time,
      // The body goes down a little when a body walks on it, and comes back like a spring.
      dip: 0,
      speed: 0,
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
    return cell >= 0 && (this.grid.kind(cell) === LAND || this.locked.has(cell));
  }

  // True if a free body can be on the cell.
  walkable(cell) {
    return this.grid.kind(cell) === LAND || this.locked.has(cell);
  }

  // Takes the news: see `this.news`.
  takeNews() {
    const news = this.news;
    this.news = { locks: [], workers: 0, food: 0, nest: false };
    return news;
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
    const locked = this.locked;
    // The cells of locked bodies that have a free body on them.
    const loaded = new Set();
    // The place of the pile that no body can walk to.
    let far = null;
    for (const pile of this.piles.values()) if (pile.far) far = [grid.x(pile.cell), grid.z(pile.cell)];
    let spare = 0;
    let carriers = 0;

    for (let id = 0; id < this.workerEnd; id++) {
      if (!w.alive[id]) continue;
      if (w.carrier[id]) carriers++;
      else spare++;
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
        w.still[id] = 0;
      } else {
        w.still[id] += dt;
        // A spare body that waits looks to the pile across the river, and its legs do not
        // stay still: it wants to go across.
        if (far && !w.carrier[id] && w.still[id] > 0.35) {
          w.heading[id] = turnToward(w.heading[id], Math.atan2(far[0] - w.x[id], far[1] - w.z[id]), dt * 5);
          w.phase[id] += dt * (5 + 4 * hash01(id * 3));
        }
      }
      if (locked.has(cell)) loaded.add(cell);
      const height = this.heightAt(w.x[id], w.z[id]);
      w.y[id] += (height - w.y[id]) * Math.min(1, dt * 12);
    }
    this.spare = spare;
    this.carriers = carriers;

    for (const [id, player] of this.players) {
      if (id === this.you) continue;
      const dx = player.tx - player.x;
      const dz = player.tz - player.z;
      const distance = Math.hypot(dx, dz);
      if (distance > 6 || player.jump) {
        player.x = player.tx;
        player.z = player.tz;
        player.jump = false;
      } else if (distance > 0.005) {
        const step = Math.min(distance, Math.max(speed, distance * 8) * dt);
        player.x += (dx / distance) * step;
        player.z += (dz / distance) * step;
        player.phase += step * 13;
      }
      player.heading = turnToward(player.heading, player.theading, dt * 12);
      player.y += (this.heightAt(player.x, player.z) - player.y) * Math.min(1, dt * 12);
      const under = grid.cellAt(player.x, player.z);
      if (under >= 0 && locked.has(under)) loaded.add(under);
    }
    if (this.me.alive) {
      const under = grid.cellAt(this.me.x, this.me.z);
      if (under >= 0 && locked.has(under)) loaded.add(under);
    }

    // The bridge lives: a locked body goes down under a load and comes back like a spring.
    const time = Math.min(dt, 0.05);
    for (const body of locked.values()) {
      const target = loaded.has(body.cell) ? -0.05 : 0;
      if (body.dip === target && body.speed === 0) continue;
      body.speed += ((target - body.dip) * 260 - body.speed * 13) * time;
      body.dip += body.speed * time;
      if (Math.abs(body.dip - target) < 0.0005 && Math.abs(body.speed) < 0.005) {
        body.dip = target;
        body.speed = 0;
      }
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
      if (next >= 0 && (grid.kind(next) === LAND || this.locked.has(next))) bits |= 1 << direction;
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
    const need = this.workerEnd + 3 * this.players.size + this.locked.size + 8;
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

    const body = (x, y, z, heading, color, phase, lock, strain, scale, legs, out = 1) => {
      bodies[b++] = x; bodies[b++] = y; bodies[b++] = z; bodies[b++] = scale;
      bodies[b++] = Math.cos(heading); bodies[b++] = Math.sin(heading); bodies[b++] = out; bodies[b++] = 0;
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

    const hide = this.hideFree;
    for (let id = 0; id < this.workerEnd && !hide; id++) {
      if (!w.alive[id] || !sees(w.x[id], w.z[id])) continue;
      const heading = w.heading[id];
      const carrier = w.carrier[id] === 1;
      // A spare body that waits moves a little to the front and back.
      const rock = w.still[id] > 0.35 && !carrier ? 0.045 * Math.sin(time * (2.6 + hash01(id * 5)) + id) : 0;
      const scale = carrier ? CARRIER_SCALE : SPARE_SCALE;
      body(w.x[id] + Math.sin(heading) * rock, w.y[id], w.z[id] + Math.cos(heading) * rock, heading, carrier ? CARRIER_COLOR : SPARE_COLOR, w.phase[id], 0, 0, scale, 0);
      shadow(w.x[id], w.y[id], w.z[id], 0.3 * scale);
      if (w.carry[id]) {
        // A unit of food, or a white egg, in front of the head.
        const egg = w.carry[id] === 2;
        const size = egg ? 0.085 : 0.08;
        crumbs[c++] = w.x[id] + Math.sin(heading) * 0.3 * scale; crumbs[c++] = w.y[id] + 0.16 * scale + (egg ? 0.03 : 0); crumbs[c++] = w.z[id] + Math.cos(heading) * 0.3 * scale; crumbs[c++] = heading;
        crumbs[c++] = size; crumbs[c++] = egg ? size * 1.35 : size; crumbs[c++] = size;
        const color = egg ? EGG_COLOR : FOOD_COLOR;
        crumbs[c++] = color[0]; crumbs[c++] = color[1]; crumbs[c++] = color[2]; crumbs[c++] = 1;
      }
    }

    // The food that a player carries: more than the one unit of a worker.
    const load = (x, y, z, heading) => {
      for (const [side, up, size] of [[0, 0.24, 0.14], [0.09, 0.2, 0.1], [-0.09, 0.2, 0.1]]) {
        crumbs[c++] = x + Math.sin(heading) * 0.36 + Math.cos(heading) * side; crumbs[c++] = y + up; crumbs[c++] = z + Math.cos(heading) * 0.36 - Math.sin(heading) * side; crumbs[c++] = side * 9;
        crumbs[c++] = size; crumbs[c++] = size; crumbs[c++] = size;
        crumbs[c++] = FOOD_COLOR[0]; crumbs[c++] = FOOD_COLOR[1]; crumbs[c++] = FOOD_COLOR[2]; crumbs[c++] = 1;
      }
    };

    for (const [id, player] of this.players) {
      if (id === this.you || hide) continue;
      body(player.x, player.y, player.z, player.heading, player.color, player.phase, 0, 0, 1.12, 0);
      shadow(player.x, player.y, player.z, 0.34);
      if (player.carry) load(player.x, player.y, player.z, player.heading);
    }

    const me = this.me;
    if (me.alive && !hide) {
      // After a lock, the new body is the body of a worker until the light gets to it.
      // Then it gets the color of the player, and it is large for a moment.
      const since = time - me.arrive;
      const mine = since >= 0;
      const pop = mine && since < 0.3 ? 0.3 * (1 - since / 0.3) : 0;
      body(me.x + me.slideX, me.y, me.z + me.slideZ, me.heading, mine ? me.color : SPARE_COLOR, me.phase, 0, 0, 1.12 + pop, 0);
      shadow(me.x + me.slideX, me.y, me.z + me.slideZ, 0.34);
      if (me.carry) load(me.x + me.slideX, me.y, me.z + me.slideZ, me.heading);
    }

    // The lowest cost of the rule: a body with less support than 2 rows of this is weak.
    const row = this.rule.costs[0];
    for (const locked of this.locked.values()) {
      if (locked.n > this.storyLimit || !sees(locked.x, locked.z)) continue;
      // The moment of a lock: the body goes from the place of its free body down into its
      // cell in 0.15 seconds. Then its legs go out to the bodies and the land that it touches.
      let x = locked.x;
      let z = locked.z;
      let y = -0.02 + locked.dip;
      let out = 1;
      const age = time - locked.start;
      if (age < 0.5) {
        const part = Math.max(0, Math.min(1, age / 0.15));
        const ease = part * part * (3 - 2 * part);
        if (locked.from) {
          x = locked.from[0] + (x - locked.from[0]) * ease;
          z = locked.from[1] + (z - locked.from[1]) * ease;
        }
        y += 0.2 * (1 - ease);
        // The legs go out fast, a small distance too far, and come back.
        const reach = Math.max(0, Math.min(1, (age - 0.1) / 0.16));
        out = 1 + 3.7 * (reach - 1) ** 3 + 2.7 * (reach - 1) ** 2;
        // The body goes below its place for a moment when it gets there.
        if (age > 0.15) y -= 0.05 * Math.sin(Math.min(1, (age - 0.15) / 0.3) * Math.PI);
      }
      const strain = Math.max(0, Math.min(1, (row - locked.support) / row + 0.4)) * (locked.support <= row ? 1 : 0);
      // All the locked bodies look to the north: each leg then has one direction.
      body(x, y, z, 0, locked.color, 0, 1, strain, 1.0, this.legs(locked.cell), out);
      // A dark plate below the body: the bridge is one structure.
      decks[d++] = locked.x; decks[d++] = -0.03 + locked.dip; decks[d++] = locked.z; decks[d++] = 0;
      decks[d++] = 1.12; decks[d++] = 1; decks[d++] = 1.12;
      decks[d++] = 0.05; decks[d++] = 0.04; decks[d++] = 0.035; decks[d++] = 0.55 * Math.min(1, Math.max(0, age / 0.15));
    }

    this.bodyCount = b / BODY_STRIDE;
    this.shadowCount = s / MESH_STRIDE;
    this.crumbCount = c / MESH_STRIDE;
    this.deckCount = d / MESH_STRIDE;
  }

  // The number of bodies in the world: free workers, players and locked bodies.
  bodyTotal() {
    return this.spare + this.carriers + this.players.size + this.locked.size;
  }
}

// A move for the server: x u16, z u32, heading u8. A position is (value + 1) * 500.
export function encodeMove(x, z, heading) {
  const buffer = new ArrayBuffer(7);
  const view = new DataView(buffer);
  const position = (value, most) => Math.max(0, Math.min(most, Math.round((value + 1) * 500)));
  const turn = Math.round((heading / (2 * Math.PI)) * 256);
  view.setUint16(0, position(x, 0xffff), true);
  view.setUint32(2, position(z, 0xffffffff), true);
  view.setUint8(6, ((turn % 256) + 256) % 256);
  return buffer;
}

export function toBase64(buffer) {
  let text = "";
  for (const byte of new Uint8Array(buffer)) text += String.fromCharCode(byte);
  return btoa(text);
}

export { FOOD_COLOR, EGG_COLOR, hash01 };
