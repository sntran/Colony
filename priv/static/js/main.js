// The page: it connects the server, the input and the picture.

import { GAP } from "./hex.js";
import { Net, encodeMove, toBase64 } from "./net.js";
import { World, MESH_STRIDE } from "./state.js";
import { Renderer } from "./render.js";
import { Input } from "./input.js";
import { myName, colorOf, cssColor, HELPER_COLOR } from "./names.js";
import * as support from "./support.js";

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
let seed = null;
let corrections = 0;
// The body that this player took cannot lock before this time.
let restUntil = 0;
// True while the page waits for the reply of a lock.
let lockPending = false;
// The time of the last reply of a lock, and the last moves that the server refused.
// A test reads them.
let lockTime = 0;
const refused = [];
// The records of the bridges, the newest first.
let records = [];

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
      me.slideX = me.slideZ = 0;
      camera.x = me.x;
      camera.z = me.z;
    }
    if (startTime === null) startTime = performance.now();
    $("status").hidden = true;
    $("top").hidden = false;
  },
  tick(buffer) {
    world.applyTick(buffer);
  },
  you(message) {
    if (message.state === "alive") {
      // A new body at the nest.
      me.alive = true;
      me.x = message.x;
      me.z = message.z;
      me.heading = 0;
      me.slideX = me.slideZ = 0;
    } else if (message.food) {
      const seconds = Math.round((performance.now() - startTime) / 1000);
      banner(`You are at the food. Time: ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`, 6000);
    } else if (typeof message.x === "number") {
      // The server did not accept a move. Go back to the position of the server.
      refused.push({
        from: [message.x, message.z],
        to: [sent.x, sent.z],
        body: [me.x, me.z],
        afterLock: Math.round(performance.now() - lockTime),
      });
      if (refused.length > 20) refused.shift();
      me.x = message.x;
      me.z = message.z;
      trail = [];
      sent = { ...sent, x: me.x, z: me.z };
      corrections++;
    }
  },
  records(list) {
    records = list;
    showRecords();
  },
  record(record) {
    records = [record, ...records.filter((other) => other.id !== record.id)].sort((a, b) => b.id - a.id);
    showRecords();
    // At the first food, each player who has a body in the bridge sees the record.
    if (record.first && record.names.some((entry) => entry.name === me.name && !entry.helper)) showCard(record);
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
// The records of the bridges

function recordElement(record) {
  const element = document.createElement("div");
  element.className = "record";
  const mine = record.names.some((entry) => entry.name === me.name && !entry.helper);
  if (mine) element.classList.add("mine");
  const when = new Date(record.time * 1000);
  const title = document.createElement("h2");
  title.textContent = `Bridge ${record.id}: ${record.rows} rows in ${record.seconds} seconds`;
  const line = document.createElement("p");
  line.textContent = `${record.bodies} bodies. ${record.food} food${record.done ? "" : " and more"}. ${when.toLocaleDateString()} ${when.toLocaleTimeString()}`;
  const names = document.createElement("ul");
  for (const entry of record.names) {
    const item = document.createElement("li");
    if (entry.helper) item.className = "helper";
    else if (entry.name === me.name) item.className = "me";
    const dot = document.createElement("i");
    dot.style.background = cssColor(entry.helper ? HELPER_COLOR : colorOf(entry.name));
    item.append(dot, `${entry.name} ${entry.bodies}`);
    names.appendChild(item);
  }
  element.append(title, line, names);
  return element;
}

function showRecords() {
  $("recordCount").textContent = `${records.length}`;
  $("empty").hidden = records.length > 0;
  $("list").replaceChildren(...records.map(recordElement));
}

let cardTimer = null;
function showCard(record) {
  $("card").replaceChildren(recordElement(record));
  $("card").hidden = false;
  clearTimeout(cardTimer);
  cardTimer = setTimeout(() => ($("card").hidden = true), 5000);
}

// Not "click": a tap of the right thumb is not a click while the left thumb is on the stick.
$("open").addEventListener("pointerup", () => {
  $("records").hidden = false;
  $("card").hidden = true;
});
$("close").addEventListener("pointerup", () => ($("records").hidden = true));

// ---------------------------------------------------------------------------
// Input

let target = -1;
let selected = -1;
let selectedTime = 0;
let selectedData = null;

const input = new Input(
  { zone: $("zone"), stick: $("stick"), knob: $("knob"), lock: $("lock"), scent: $("scent"), canvas },
  {
    lock() {
      if (demo || !me.alive || target < 0 || performance.now() < restUntil) return refuse();
      const cell = target;
      const at = toBase64(encodeMove(me.x, me.z, me.heading, input.scent));
      // The page sends no position while it waits for the reply: after the lock, the
      // player has a different body, and a position of the old body is wrong.
      lockPending = true;
      net.lock(cell, at).then((body) => {
        lockPending = false;
        lockTime = performance.now();
        if (!body) return refuse();
        if (typeof body.x === "number") {
          // The player has the body of a worker now. The picture goes to it smoothly.
          const from = world.takeWorker(body.worker);
          me.slideX = from ? from[0] - body.x : 0;
          me.slideZ = from ? from[1] - body.z : 0;
          if (from) me.heading = from[2];
          me.x = body.x;
          me.z = body.z;
          sent = { ...sent, x: body.x, z: body.z };
          trail = [];
          restUntil = performance.now() + 1000;
        } else {
          // The colony has no free worker. A new body comes at the nest after some seconds.
          me.alive = false;
        }
      });
    },
    tap(x, y) {
      // Show the name, the time and the count of a locked body.
      if (!world.ready) return;
      const point = renderer.pick(x, y, 0.08);
      const cell = point ? world.grid.cellAt(point[0], point[1]) : -1;
      selected = cell >= 0 && world.locked.has(cell) ? cell : -1;
      selectedTime = performance.now();
      selectedData = null;
      if (selected >= 0) {
        net.body(selected).then((data) => {
          if (data && selected === cell) selectedData = data;
        });
      }
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
      // A position in a message has 3 decimals. The body is always at such a position:
      // the page and the server then find the same cell for it.
      const nx = Math.round((me.x + ((dx * cos - dz * sin) / length) * step * cos) * 1000) / 1000;
      const nz = Math.round((me.z + ((dx * sin + dz * cos) / length) * step * cos) * 1000) / 1000;
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
//
// The server looks at the straight way from one position to the next. After a long
// frame, the body is far from its last position, and the straight way can go across a
// corner of the river. Thus the page keeps the points of the way and sends them all.
let sent = { x: 0, z: 0, heading: 0, scent: false, time: 0 };
let trail = [];

function trackMove() {
  const from = trail.length > 0 ? trail[trail.length - 1] : sent;
  if (Math.hypot(me.x - from.x, me.z - from.z) >= 0.45) trail.push({ x: me.x, z: me.z });
}

function sendMove(now) {
  if (!me.alive || demo || lockPending) {
    trail = [];
    return;
  }
  if (now - sent.time < 100) return;
  if (me.x === sent.x && me.z === sent.z && me.scent === sent.scent && Math.abs(me.heading - sent.heading) < 0.05) return;
  for (const point of trail) {
    if (point.x !== me.x || point.z !== me.z) net.move(encodeMove(point.x, point.z, me.heading, me.scent));
  }
  trail = [];
  net.move(encodeMove(me.x, me.z, me.heading, me.scent));
  sent = { x: me.x, z: me.z, heading: me.heading, scent: me.scent, time: now };
}

// ---------------------------------------------------------------------------
// The cells where a lock is possible, and the reach of the bridge

const rings = new Float32Array(MESH_STRIDE * 9);
const cells = new Float32Array(MESH_STRIDE * 2);
const marks = new Float32Array(MESH_STRIDE * 40);

// The page calculates these again only when the bodies change or the body goes to a new cell.
let optionsKey = "";
let options = [];
let reachKey = "";
let reach = null;

function markCells(time) {
  let ringCount = 0;
  let cellCount = 0;
  let markCount = 0;
  target = -1;
  if (me.alive && !demo) {
    const grid = world.grid;
    const here = grid.cellAt(me.x, me.z);
    const key = `${world.structure}:${here}`;
    if (key !== optionsKey) {
      optionsKey = key;
      options = [];
      for (const next of here >= 0 ? grid.neighbors(here) : []) {
        if (grid.kind(next) !== GAP || world.locked.has(next)) continue;
        options.push([next, support.canLock(grid, world.rule, world.locked, next)]);
      }
    }

    // Take the cell in the direction that the body looks.
    const facing = [Math.sin(me.heading), Math.cos(me.heading)];
    let best = -Infinity;
    for (const [cell, possible] of options) {
      if (!possible) continue;
      const dx = grid.x(cell) - me.x;
      const dz = grid.z(cell) - me.z;
      const score = (dx * facing[0] + dz * facing[1]) / (Math.hypot(dx, dz) || 1);
      if (score > best) {
        best = score;
        target = cell;
      }
    }

    const pulse = 0.5 + 0.5 * Math.sin(time * 6);
    const put = (list, index, x, y, z, turn, size, color, alpha) => {
      list.set([x, y, z, turn, size, 1, size, color[0], color[1], color[2], alpha], index * MESH_STRIDE);
    };
    // A ring on the ground shows the body of this player between the workers.
    put(rings, ringCount++, me.x + me.slideX, me.y + 0.04, me.z + me.slideZ, time * 0.8, 0.82, [1, 1, 1], 0.55);
    for (const [cell, possible] of options) {
      const x = grid.x(cell);
      const z = grid.z(cell);
      if (cell === target) {
        put(cells, cellCount++, x, 0.05, z, 0, 1, [1, 0.86, 0.3], 0.4 + 0.25 * pulse);
        put(rings, ringCount++, x, 0.05, z, 0, 1, [1, 1, 0.9], 1);
      } else if (possible) {
        put(rings, ringCount++, x, 0.05, z, 0, 1, [1, 0.9, 0.45], 0.75);
      } else {
        put(rings, ringCount++, x, 0.05, z, 0, 1, [0.9, 0.15, 0.1], 0.5);
      }
    }

    // The reach: one mark on each row that the bridge can get to, if the player locks into
    // the selected cell and then continues one body wide. No words.
    if (target >= 0) {
      const key = `${world.structure}:${target}`;
      if (key !== reachKey) {
        reachKey = key;
        reach = support.reach(grid, world.rule, world.locked, target);
      }
      reach.cells.forEach((cell, index) => {
        // A wave goes along the marks, away from the bridge.
        const wave = 0.5 + 0.5 * Math.sin(time * 5 - index * 0.9);
        put(marks, markCount++, grid.x(cell), 0.04, grid.z(cell), 0, 0.2 + 0.05 * wave, [1, 0.95, 0.6], 0.65 + 0.35 * wave);
      });
      if (reach.bank >= 0) {
        // The bridge can get to the far bank: a large mark there.
        const wave = 0.5 + 0.5 * Math.sin(time * 5 - reach.cells.length * 0.9);
        put(marks, markCount++, grid.x(reach.bank), 0.06, grid.z(reach.bank), 0, 0.36 + 0.08 * wave, [0.55, 1, 0.5], 0.95);
      } else if (reach.next >= 0 && reach.part > 0.02) {
        // The first row that the bridge cannot get to: a small mark that grows when the
        // bridge gets more support.
        put(marks, markCount++, grid.x(reach.next), 0.04, grid.z(reach.next), 0, 0.05 + 0.13 * reach.part, [1, 0.6, 0.35], 0.35 + 0.4 * reach.part);
      }
    } else {
      reachKey = "";
    }
  }
  renderer.fill("rings", rings, ringCount);
  renderer.fill("cells", cells, cellCount);
  renderer.fill("marks", marks, markCount);
  $("lock").classList.toggle("ready", target >= 0 && performance.now() >= restUntil);
}

// ---------------------------------------------------------------------------
// The camera

const camera = { x: 30, z: 5, turn: 0, height: 10, distance: 10, fov: (55 * Math.PI) / 180 };
const AHEAD = 2.2;

function moveCamera(dt, time) {
  const grid = world.grid;
  if (demo) {
    // The camera goes slowly to the place where the helpers build, and turns slowly.
    let x = 0;
    let z = 0;
    let count = 0;
    for (const player of world.players.values()) {
      if (!player.helper) continue;
      x += player.x;
      z += player.z;
      count++;
    }
    if (count === 0) {
      x = grid.x(world.nest);
      z = grid.z(world.nest);
      count = 1;
    }
    // Look between the helpers and the pile.
    const tx = (x / count) * 0.6 + grid.x(world.pile.cell) * 0.4;
    const tz = (z / count) * 0.6 + grid.z(world.pile.cell) * 0.4 - 1;
    const follow = 1 - Math.exp(-dt * 0.5);
    camera.x += (tx + Math.sin(time * 0.11) * 1.2 - camera.x) * follow;
    camera.z += (tz - camera.z) * follow;
    camera.turn = 0.3 * Math.sin(time * 0.13 + 0.6);
    // A tall screen shows a narrow part of the world. The camera goes back to show more.
    const far = canvas.clientWidth < canvas.clientHeight ? 1.5 : 1;
    camera.height = 8.2 * far;
    camera.distance = 9 * far;
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

const FOOD_SIGN = '<svg viewBox="0 0 24 24"><circle cx="8" cy="15" r="5" fill="#ffbd33"/><circle cx="16" cy="15.5" r="4.4" fill="#ffc94d"/><circle cx="12.5" cy="8.5" r="4.6" fill="#ffd76a"/></svg>';
const labels = new Map();
let pileLabel = null;

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
      label.className = player.helper ? "helper" : "";
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

  // The number of units of the pile, above the pile.
  if (!pileLabel) {
    pileLabel = document.createElement("div");
    pileLabel.className = "pile";
    pileLabel.innerHTML = `${FOOD_SIGN}<span></span>`;
    $("labels").appendChild(pileLabel);
  }
  const pileAt = renderer.project(world.grid.x(world.pile.cell), 1.5, world.grid.z(world.pile.cell));
  pileLabel.hidden = !pileAt;
  if (pileAt) {
    pileLabel.lastChild.textContent = `${world.pile.units}`;
    pileLabel.style.left = `${pileAt[0]}px`;
    pileLabel.style.top = `${pileAt[1]}px`;
  }

  // A mark above the body of this player.
  const mark = me.alive && !demo ? renderer.project(me.x + me.slideX, me.y + 0.62, me.z + me.slideZ) : null;
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
    info.innerHTML = "";
    info.appendChild(document.createElement("b")).textContent = body.name;
    info.append(`Locked ${when.toLocaleDateString()} ${when.toLocaleTimeString()}`);
    if (selectedData) {
      info.append(document.createElement("br"), `${selectedData.crossings} bodies went across`);
    }
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
    for (let left = dt; left > 0.0001; left -= 1 / 30) {
      moveMe(Math.min(left, 1 / 30));
      trackMove();
    }
    sendMove(now);
    world.update(dt);
    markCells(time);
    moveCamera(dt, time);
    world.build((x, z) => renderer.sees(x, z));
    renderer.fill("bodies", world.bodies, world.bodyCount);
    renderer.fill("shadows", world.shadows, world.shadowCount);
    renderer.fill("crumbs", world.crumbs, world.crumbCount);
    renderer.fill("decks", world.decks, world.deckCount);
    if (world.scentDirty) {
      renderer.setScent(world);
      world.scentDirty = false;
    }
    if (world.foodDirty) {
      renderer.setFood(world);
      world.foodDirty = false;
    }
    renderer.draw(world, time);
    drawLabels();
    // The free workers are the bodies that the colony can still use.
    $("workerCount").textContent = `${world.freeWorkers}`;
    $("workers").classList.toggle("low", world.freeWorkers < 5);
    $("foodCount").textContent = `${world.foodNest}`;
  } else {
    renderer.draw(world, 0);
  }
}
requestAnimationFrame(frame);

// For tests in a browser.
window.colony = {
  world,
  net,
  camera,
  renderer,
  support,
  target: () => target,
  reach: () => reach,
  options: () => options,
  records: () => records,
  resting: () => performance.now() < restUntil,
  corrections: () => corrections,
  refused: () => refused,
};
