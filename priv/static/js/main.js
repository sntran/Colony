// The page: it connects the server, the input and the picture.

import { GAP } from "./hex.js";
import { Net, encodeMove, toBase64 } from "./net.js";
import { World, MESH_STRIDE } from "./state.js";
import { Renderer } from "./render.js";
import { Input } from "./input.js";
import { myName, colorOf, cssColor } from "./names.js";

const params = new URLSearchParams(location.search);
const demo = params.get("demo") === "1";
const showStats = params.get("stats") === "1";
// "?scale=1" sets the number of canvas pixels for each page pixel and stops the automatic change.
const fixedScale = parseFloat(params.get("scale")) || 0;

const $ = (id) => document.getElementById(id);
const canvas = $("view");
const world = new World();
const me = world.me;
me.name = myName();
me.color = colorOf(me.name);

let renderer;
try {
  renderer = new Renderer(canvas);
} catch (error) {
  $("status").textContent = error.message;
  throw error;
}
if (fixedScale) renderer.scale = fixedScale;

// The touch controls show on a device with a touch screen. The key help shows on the others.
const setTouch = () => {
  document.body.classList.remove("keys");
  document.body.classList.add("touch");
};
if (matchMedia("(pointer: coarse)").matches) setTouch();
window.addEventListener("touchstart", setTouch, { once: true, passive: true });
if (demo) document.body.classList.add("demo");

$("name").textContent = me.name;
$("swatch").style.background = cssColor(me.color);

// ---------------------------------------------------------------------------
// Messages from the server

let startTime = null;
let corrections = 0;
let seed = null;
let dead = null;

const net = new Net(me.name, demo, {
  snapshot(buffer) {
    world.snapshot(buffer);
    if (seed !== world.seed) {
      seed = world.seed;
      renderer.setWorld(world);
    }
    world.scentDirty = true;
    world.foodDirty = true;
    const mine = world.players.get(world.you);
    me.alive = Boolean(mine);
    if (mine) {
      me.x = mine.tx;
      me.z = mine.tz;
      me.heading = 0;
      camera.x = me.x;
      camera.z = me.z;
    }
    if (startTime === null) startTime = performance.now();
    $("status").hidden = true;
    $("me").hidden = demo;
    $("food").hidden = false;
  },
  tick(buffer) {
    world.applyTick(buffer);
  },
  you(message) {
    if (message.state === "dead") {
      me.alive = false;
      dead = message.reason;
      if (message.reason === "fell") {
        world.ghosts.push({ x: me.x, y: me.y, z: me.z, heading: me.heading, color: me.color, speed: 0, tilt: 0 });
        banner("You fell", 1500);
      }
    } else if (message.state === "alive") {
      me.alive = true;
      me.x = message.x;
      me.z = message.z;
      me.heading = 0;
      dead = null;
    } else if (message.food) {
      const seconds = Math.round((performance.now() - startTime) / 1000);
      banner(`You are at the food. Time: ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`, 8000);
    } else if (typeof message.x === "number") {
      // The server did not accept a move. Go back to the position of the server.
      me.x = message.x;
      me.z = message.z;
      corrections++;
    }
  },
  status(text) {
    $("status").textContent = text;
    $("status").hidden = text === "" && world.ready;
  },
});

let bannerTimer = null;
function banner(text, time) {
  const element = $("banner");
  element.textContent = text;
  element.hidden = false;
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => (element.hidden = true), time);
}

// ---------------------------------------------------------------------------
// Input

let target = -1;
let selected = -1;
let selectedTime = 0;

const input = new Input(
  { zone: $("zone"), stick: $("stick"), knob: $("knob"), lock: $("lock"), scent: $("scent"), canvas },
  {
    lock() {
      if (demo || !me.alive || target < 0) return refuse();
      const at = toBase64(encodeMove(me.x, me.z, me.heading, input.scent));
      net.lock(target, at).then((ok) => {
        // The body is locked now. The server sends the new body after one second.
        if (ok) me.alive = false;
        else refuse();
      });
    },
    tap(x, y) {
      // Show the name and the time of a locked body.
      if (!world.ready) return;
      const point = renderer.pick(x, y, 0.08);
      const cell = point ? world.grid.cellAt(point[0], point[1]) : -1;
      selected = cell >= 0 && world.locked.has(cell) ? cell : -1;
      selectedTime = performance.now();
    },
  }
);

function refuse() {
  const button = $("lock");
  button.classList.remove("no");
  void button.offsetWidth;
  button.classList.add("no");
}

const SLIDE = [0, 0.45, -0.45, 0.9, -0.9, 1.3, -1.3];

// Moves the body of this player. The body stays on the cells where a body can be.
function moveMe(dt) {
  if (!me.alive) return;
  // On the screen, right is the -x direction of the world and up is the +z direction.
  const dx = -input.x;
  const dz = input.y;
  const length = Math.hypot(dx, dz);
  if (length > 0.01) {
    const step = world.speed * Math.min(1, length) * dt;
    // If the way is not free, the body slides along the edge: it tries directions that are
    // more and more to the side, and it goes slower.
    for (const angle of SLIDE) {
      const cos = Math.cos(angle);
      const sin = Math.sin(angle);
      const nx = me.x + ((dx * cos - dz * sin) / length) * step * cos;
      const nz = me.z + ((dx * sin + dz * cos) / length) * step * cos;
      if (world.canStand(nx, nz)) {
        me.x = nx;
        me.z = nz;
        break;
      }
    }
    let turn = Math.atan2(dx, dz) - me.heading;
    while (turn > Math.PI) turn -= 2 * Math.PI;
    while (turn < -Math.PI) turn += 2 * Math.PI;
    me.heading += turn * Math.min(1, dt * 14);
    me.phase += step * 13;
  }
  me.y += (world.heightAt(me.x, me.z) - me.y) * Math.min(1, dt * 12);
  me.scent = input.scent;
}

// Sends the position 10 times each second, but only if something changed.
let sent = { x: 0, z: 0, heading: 0, scent: false, time: 0 };
function sendMove(now) {
  if (!me.alive || demo || now - sent.time < 100) return;
  if (me.x === sent.x && me.z === sent.z && me.scent === sent.scent && Math.abs(me.heading - sent.heading) < 0.05) return;
  net.move(encodeMove(me.x, me.z, me.heading, me.scent));
  sent = { x: me.x, z: me.z, heading: me.heading, scent: me.scent, time: now };
}

// ---------------------------------------------------------------------------
// The cells where a lock is possible

const rings = new Float32Array(MESH_STRIDE * 9);
const cells = new Float32Array(MESH_STRIDE * 2);

function markCells(time) {
  let ringCount = 0;
  let cellCount = 0;
  target = -1;
  if (me.alive && !demo) {
    const grid = world.grid;
    const here = grid.cellAt(me.x, me.z);
    const facing = [Math.sin(me.heading), Math.cos(me.heading)];
    let best = -Infinity;
    const options = [];
    for (const next of here >= 0 ? grid.neighbors(here) : []) {
      if (grid.kind(next) !== GAP || world.locked.has(next)) continue;
      const possible = world.frontier.has(next);
      options.push([next, possible]);
      if (possible) {
        // Take the cell in the direction that the body looks.
        const dx = grid.x(next) - me.x;
        const dz = grid.z(next) - me.z;
        const score = (dx * facing[0] + dz * facing[1]) / (Math.hypot(dx, dz) || 1);
        if (score > best) {
          best = score;
          target = next;
        }
      }
    }
    const pulse = 0.5 + 0.5 * Math.sin(time * 6);
    const put = (list, index, cell, color, alpha) => {
      list.set([grid.x(cell), 0.05, grid.z(cell), 0, 1, 1, 1, color[0], color[1], color[2], alpha], index * MESH_STRIDE);
    };
    // A ring on the ground shows the body of this player between the workers.
    rings.set([me.x, me.y + 0.04, me.z, time * 0.8, 0.82, 1, 0.82, 1, 1, 1, 0.55], ringCount++ * MESH_STRIDE);
    for (const [cell, possible] of options) {
      if (cell === target) {
        put(cells, cellCount++, cell, [1, 0.86, 0.3], 0.4 + 0.25 * pulse);
        put(rings, ringCount++, cell, [1, 1, 0.9], 1);
      } else if (possible) {
        put(rings, ringCount++, cell, [1, 0.9, 0.45], 0.75);
      } else {
        put(rings, ringCount++, cell, [0.9, 0.15, 0.1], 0.5);
      }
    }
  }
  renderer.fill("rings", rings, ringCount);
  renderer.fill("cells", cells, cellCount);
  $("lock").classList.toggle("ready", target >= 0);
}

// ---------------------------------------------------------------------------
// The camera

const camera = { x: 30, z: 5, turn: 0, height: 10, distance: 10, fov: (55 * Math.PI) / 180 };
const AHEAD = 2.2;

function moveCamera(dt, time) {
  const grid = world.grid;
  if (demo) {
    // A slow move from the nest to the middle of the gap, with a slow turn.
    const nestZ = grid.z(world.nest);
    const gapZ = (grid.nearRows + grid.gapRows / 2 - 0.5) * 0.866;
    const part = Math.min(1, Math.max(0, (time - 2) / 12));
    const ease = part * part * (3 - 2 * part);
    camera.x = grid.x(world.nest) + Math.sin(time * 0.11) * 1.2;
    camera.z = nestZ + 1.5 + (gapZ - nestZ - 1.5) * ease + Math.sin(time * 0.17) * 0.8;
    camera.turn = 0.32 * Math.sin(time * 0.13 + 0.6);
    // A tall screen shows a narrow part of the world. The camera goes back to show more.
    const far = canvas.clientWidth < canvas.clientHeight ? 1.45 : 1;
    camera.height = (6.6 + 1.2 * ease) * far;
    camera.distance = 8.4 * far;
    camera.fov = (50 * Math.PI) / 180;
  } else {
    const follow = 1 - Math.exp(-dt * (me.alive ? 6 : 1.5));
    camera.x += (me.x - camera.x) * follow;
    camera.z += (me.z + AHEAD - camera.z) * follow;
  }
  renderer.setCamera(camera);
}

// ---------------------------------------------------------------------------
// Text above the picture

const labels = new Map();
function drawLabels() {
  for (const [id, player] of world.players) {
    if (id === world.you) continue;
    let label = labels.get(id);
    if (!label) {
      label = document.createElement("div");
      $("labels").appendChild(label);
      labels.set(id, label);
    }
    const at = renderer.project(player.x, player.y + 0.55, player.z);
    label.hidden = !at;
    if (at) {
      label.textContent = player.name;
      label.style.left = `${at[0]}px`;
      label.style.top = `${at[1]}px`;
    }
  }
  for (const [id, label] of labels) {
    if (!world.players.has(id) || id === world.you) {
      label.remove();
      labels.delete(id);
    }
  }

  // A mark above the body of this player.
  const mark = me.alive && !demo ? renderer.project(me.x, me.y + 0.62, me.z) : null;
  $("you").hidden = !mark;
  if (mark) {
    $("you").style.left = `${mark[0]}px`;
    $("you").style.top = `${mark[1]}px`;
  }

  const info = $("info");
  const body = selected >= 0 ? world.locked.get(selected) : null;
  const at = body && performance.now() - selectedTime < 6000 ? renderer.project(body.x, 0.3, body.z) : null;
  info.hidden = !at;
  if (at) {
    const when = new Date(body.time * 1000);
    const title = body.kind === 1 ? body.name : "Worker";
    info.innerHTML = "";
    info.appendChild(document.createElement("b")).textContent = title;
    info.append(`Locked ${when.toLocaleDateString()} ${when.toLocaleTimeString()}`);
    info.style.left = `${at[0]}px`;
    info.style.top = `${at[1]}px`;
  }
}

let frames = 0;
let slowFrames = 0;
let lastSecond = performance.now();
function everySecond(now) {
  const seconds = (now - lastSecond) / 1000;
  const fps = frames / seconds;
  const bytes = net.takeBytes() / seconds;
  if (showStats) {
    $("stats").hidden = false;
    $("stats").textContent =
      `frames each second  ${fps.toFixed(0)}\n` +
      `bodies              ${world.bodyTotal()}\n` +
      `delay to server     ${net.delay.toFixed(0)} ms\n` +
      `bytes each second   ${Math.round(bytes)}`;
    net.ping();
  }
  $("count").textContent = `${world.foodNest}`;

  // If the picture is slow for some seconds, use fewer pixels.
  if (!fixedScale && world.ready) {
    slowFrames = fps < 27 ? slowFrames + 1 : 0;
    if (slowFrames >= 3 && renderer.scale > 0.8) {
      renderer.scale = Math.max(0.8, renderer.scale * 0.8);
      slowFrames = 0;
    }
  }
  frames = 0;
  lastSecond = now;
}

// ---------------------------------------------------------------------------
// Each frame

let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  // A slow frame does not make the game slow: the time of the frame is the real time.
  const dt = Math.min(0.25, (now - last) / 1000);
  last = now;
  frames++;
  if (now - lastSecond >= 1000) everySecond(now);
  renderer.resize();

  if (world.ready) {
    const time = world.time;
    // Small steps keep the body on its cells when a frame is long.
    for (let left = dt; left > 0.0001; left -= 1 / 30) moveMe(Math.min(left, 1 / 30));
    sendMove(now);
    world.update(dt);
    markCells(time);
    moveCamera(dt, time);
    world.build((x, z) => renderer.sees(x, z));
    renderer.fill("bodies", world.bodies, world.bodyCount);
    renderer.fill("shadows", world.shadows, world.shadowCount);
    renderer.fill("crumbs", world.crumbs, world.crumbCount);
    if (world.scentDirty) {
      renderer.setScent(world);
      world.scentDirty = false;
    }
    if (world.foodDirty) {
      renderer.setFood(world.foodPile, world.foodUnits, world.foodNest);
      world.foodDirty = false;
    }
    renderer.draw(world, time);
    drawLabels();
  } else {
    renderer.draw(world, 0);
  }
}
requestAnimationFrame(frame);

// For tests in a browser.
window.colony = { world, net, camera, renderer, target: () => target, corrections: () => corrections };
