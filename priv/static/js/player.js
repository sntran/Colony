// The body of this player: how it moves, what it sends to the server, and the lock.
//
// This file uses no page and no picture. A test player with no browser uses it also.
// `link` sends the messages: { move(buffer), lock(cell, at) }. `lock` returns a promise
// of the new body { x, z, worker }, or of null if the server refused the lock.

import { encodeMove, toBase64 } from "./state.js";

// If the way is not free, the body slides along the edge: it tries directions that are
// more and more to the side.
const SLIDE = [0, 0.45, -0.45, 0.9, -0.9, 1.3, -1.3];
// The longest step of the body in one calculation. Small steps keep the body on its cells.
const STEP_TIME = 1 / 30;
// A position in a message has a step of 1 / 500. The body is always at such a position:
// the page and the server then find the same cell for it.
const round = (value) => Math.round(value * 500) / 500;

export class Player {
  constructor(world, guide, link) {
    this.world = world;
    this.guide = guide;
    this.link = link;
    this.me = world.me;
    // The open cell that a lock uses now, or -1.
    this.target = -1;
    // The guide now: see guide.js.
    this.current = null;
    // My last act: "lock", "carry" or null. The rule "share the work" uses it.
    this.last = null;
    this.carried = false;
    // The body that this player took cannot lock before this time, in milliseconds.
    this.restUntil = 0;
    // True while the page waits for the reply of a lock.
    this.lockPending = false;
    this.lockTime = 0;
    // The last position that the server has, and the points of the way after it.
    this.sent = { x: 0, z: 0, heading: 0, time: 0 };
    this.trail = [];
    // The direction of the last push of the stick, in the world.
    this.push = [0, 1];
    // The time that the body continues around a corner, and the push that started it.
    this.aroundLeft = 0;
    this.aroundPush = [0, 1];
    // Numbers for the tests.
    this.locks = 0;
    // The locks that the server refused.
    this.noLocks = 0;
    // For each lock: the cell, and the distance in cells from it to the new body.
    this.lockLog = [];
    this.corrections = 0;
    this.refused = [];
    // The distance that the body walked. The sound of the steps uses it.
    this.walked = 0;
  }

  // The body is at a position of the server: at the start, and after a lock.
  place(x, z) {
    const me = this.me;
    me.x = x;
    me.z = z;
    this.sent = { ...this.sent, x, z };
    this.trail = [];
  }

  // Moves the body for `dt` seconds. (sx, sy) is the stick: right and up on the screen.
  step(dt, sx, sy) {
    const me = this.me;
    if (me.alive) {
      for (let left = dt; left > 0.0001; left -= STEP_TIME) {
        this.walk(Math.min(left, STEP_TIME), sx, sy);
        const from = this.trail.length > 0 ? this.trail[this.trail.length - 1] : this.sent;
        if (Math.hypot(me.x - from.x, me.z - from.z) >= 0.45) this.trail.push({ x: me.x, z: me.z });
      }
      // The cell for a lock is in the direction of the stick. With no push, it is in the
      // direction that the body looks.
      const still = Math.hypot(sx, sy) <= 0.01;
      const dx = still ? Math.sin(me.heading) : this.push[0];
      const dz = still ? Math.cos(me.heading) : this.push[1];
      this.target = this.guide.lockCell(me.x, me.z, dx, dz);
    } else {
      this.target = -1;
    }
    // When my food gets into the nest, my last act is "carry".
    if (this.carried && !me.carry) this.last = "carry";
    this.carried = me.carry;
    this.current = this.guide.guide(me, this.last);
  }

  walk(dt, sx, sy) {
    const me = this.me;
    const world = this.world;
    // On the screen, right is the -x direction of the world and up is the +z direction.
    const dx = -sx;
    const dz = sy;
    const length = Math.hypot(dx, dz);
    if (length > 0.01) {
      this.push = [dx / length, dz / length];
      const step = world.speed * Math.min(1, length) * dt;
      const nx = dx / length;
      const nz = dz / length;
      // While the body goes around a corner, it continues along the way for a moment, if
      // the stick keeps its direction.
      const around = this.aroundLeft > 0 && nx * this.aroundPush[0] + nz * this.aroundPush[1] > 0.8;
      this.aroundLeft = around ? this.aroundLeft - dt : 0;
      let moved = around && this.around(nx, nz, step);
      for (let i = 0; i < SLIDE.length && !moved; i++) {
        const cos = Math.cos(SLIDE[i]);
        const sin = Math.sin(SLIDE[i]);
        moved = this.moveTo(me.x + (nx * cos - nz * sin) * step * cos, me.z + (nx * sin + nz * cos) * step * cos);
      }
      if (!moved && !around && this.around(nx, nz, step)) {
        this.aroundLeft = 0.5;
        this.aroundPush = [nx, nz];
      }
      let turn = Math.atan2(dx, dz) - me.heading;
      while (turn > Math.PI) turn -= 2 * Math.PI;
      while (turn < -Math.PI) turn += 2 * Math.PI;
      me.heading += turn * Math.min(1, dt * 14);
      me.phase += step * 13;
    }
    me.y += (world.heightAt(me.x, me.z) - me.y) * Math.min(1, dt * 12);
  }

  // Moves the body to a point, if a body can stand there. Returns true if the body moved.
  moveTo(x, z) {
    const me = this.me;
    const nx = round(x);
    const nz = round(z);
    if ((nx === me.x && nz === me.z) || !this.world.canStand(nx, nz)) return false;
    this.walked += Math.hypot(nx - me.x, nz - me.z);
    me.x = nx;
    me.z = nz;
    return true;
  }

  // The push is blocked: water is in the way. If the player pushes in the direction of the
  // goal of the arrow, the body goes along the way on foot to that goal: around the
  // corner of a bridge, or to the start of a bridge. Thus "push at what you see" works.
  // Returns true if the body moved.
  around(dx, dz, step) {
    const me = this.me;
    const guide = this.guide.guide(me, this.last);
    const route = guide ? guide.route : null;
    if (!route || route.steps === 0) return false;
    // Only if the goal is in front of the push, not behind it.
    if ((route.x - me.x) * dx + (route.z - me.z) * dz <= 0) return false;
    const ax = route.aimX - me.x;
    const az = route.aimZ - me.z;
    const distance = Math.hypot(ax, az);
    if (distance < 0.02) return false;
    const length = Math.min(distance, step * 0.8);
    // The way can go exactly along the edge of a cell. A small turn keeps the body on the cell.
    for (const angle of [0, 0.3, -0.3, 0.6, -0.6]) {
      const cos = Math.cos(angle);
      const sin = Math.sin(angle);
      if (this.moveTo(me.x + ((ax * cos - az * sin) / distance) * length, me.z + ((ax * sin + az * cos) / distance) * length)) return true;
    }
    return false;
  }

  // Sends the position 10 times each second, but only if something changed.
  //
  // The server looks at the straight way from one position to the next. After a long
  // frame, the body is far from its last position, and the straight way can go across a
  // corner of the river. Thus the page keeps the points of the way and sends them all.
  send(now) {
    const me = this.me;
    const sent = this.sent;
    if (!me.alive || this.lockPending) {
      this.trail = [];
      return;
    }
    if (now - sent.time < 100) return;
    if (me.x === sent.x && me.z === sent.z && Math.abs(me.heading - sent.heading) < 0.05) return;
    for (const point of this.trail) {
      if (point.x !== me.x || point.z !== me.z) this.link.move(encodeMove(point.x, point.z, me.heading));
    }
    this.trail = [];
    this.link.move(encodeMove(me.x, me.z, me.heading));
    this.sent = { x: me.x, z: me.z, heading: me.heading, time: now };
  }

  // True if a tap on the button locks: an open cell touches the cell of the body, the
  // colony has a spare body, and the body can lock.
  ready(now) {
    return this.me.alive && !this.me.carry && this.target >= 0 && this.world.spare > 0 && now >= this.restUntil && !this.lockPending;
  }

  // The state of the button: the first state that applies.
  //   "food": I carry food. "none": the colony has no spare body. "rest": my new body
  //   rests. "lock": a lock is possible. "wait": the guide has no target. "dim": my cell
  //   does not touch an open cell.
  button(now) {
    const me = this.me;
    if (!me.alive) return "dim";
    if (me.carry) return "food";
    if (this.world.spare === 0) return "none";
    if (now < this.restUntil) return "rest";
    if (this.ready(now)) return "lock";
    if (!this.current) return "wait";
    return "dim";
  }

  // Locks the body into the open cell. Returns a promise of the result:
  // { cell, from: [x, z], to: [x, z] } for a lock, "carry" if my body carries food,
  // "spare" if the colony has no spare body, or null if a lock is not possible.
  lock(now, clock = () => now) {
    const me = this.me;
    const world = this.world;
    if (!me.alive || this.lockPending) return Promise.resolve(null);
    // A body that carries food cannot lock.
    if (me.carry) return Promise.resolve("carry");
    if (world.spare === 0) return Promise.resolve("spare");
    if (!this.ready(now)) return Promise.resolve(null);
    const cell = this.target;
    const at = toBase64(encodeMove(me.x, me.z, me.heading));
    // The page sends no position while it waits for the reply: after the lock, the player
    // has a different body, and a position of the old body is wrong.
    this.lockPending = true;
    return this.link.lock(cell, at).then((body) => {
      this.lockPending = false;
      this.lockTime = clock();
      // A second player got the cell first, or the last spare body: no error on the screen.
      if (!body || typeof body.x !== "number") {
        this.noLocks++;
        return null;
      }
      // The player has the body of a worker now. The picture goes to it smoothly.
      const from = [me.x, me.z];
      const picture = world.takeWorker(body.worker);
      if (picture) me.heading = picture[2];
      this.place(body.x, body.z);
      this.restUntil = clock() + 1000;
      this.last = "lock";
      this.locks++;
      const grid = world.grid;
      this.lockLog.push({ cell, distance: Math.hypot(body.x - grid.x(cell), body.z - grid.z(cell)) });
      return { cell, from, to: [body.x, body.z] };
    });
  }

  // The server did not accept a move. The body goes back to the position of the server.
  correct(message, now) {
    const me = this.me;
    this.refused.push({ from: [message.x, message.z], to: [this.sent.x, this.sent.z], body: [me.x, me.z], afterLock: Math.round(now - this.lockTime) });
    if (this.refused.length > 20) this.refused.shift();
    this.place(message.x, message.z);
    this.corrections++;
  }
}
