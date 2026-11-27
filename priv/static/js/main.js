// The page: it connects the server, the input and the picture.

import { Net } from "./net.js";
import { World, MESH_STRIDE } from "./state.js";
import { Renderer } from "./render.js";
import { Input } from "./input.js";
import { Guide } from "./guide.js";
import { Player } from "./player.js";
import { PLAYER_CAMERA } from "./view.js";
import { myName, colorOf, cssColor, HELPER_COLOR } from "./names.js";
import { SIGNS, putSigns, sign } from "./signs.js";

const params = new URLSearchParams(location.search);
// A page that only looks has no body in the world.
const look = params.get("demo") === "1" || params.get("story") === "1";
const showStats = params.get("stats") === "1";
// "?scale=1" sets the number of canvas pixels for each page pixel and stops the automatic change.
const fixedScale = parseFloat(params.get("scale")) || 0;

const $ = (id) => document.getElementById(id);
const canvas = $("view");
const world = new World();
const me = world.me;
me.name = myName();
me.color = colorOf(me.name);
putSigns(document);

let renderer;
try {
  renderer = new Renderer(canvas);
} catch (error) {
  // This browser cannot draw the game. The sign of the wait stays.
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
if (look) document.body.classList.add("look");

$("name").textContent = me.name;
$("swatch").style.background = cssColor(me.color);

// ---------------------------------------------------------------------------
// Messages from the server

let seed = null;
// The records of the bridges, the newest first.
let records = [];
// The time of the load of the page, and the time of the first food at the nest. A test reads them.
const loadTime = performance.now();
let firstFood = null;

const guide = new Guide(world);
let player;

const net = new Net(me.name, look, {
  snapshot(buffer) {
    world.snapshot(buffer);
    if (seed !== world.seed) {
      seed = world.seed;
      renderer.setWorld(world);
    }
    world.scentDirty = true;
    world.foodDirty = true;
    solidKey = -1;
    const mine = world.players.get(world.you);
    me.alive = Boolean(mine);
    if (mine) {
      player.place(mine.tx, mine.tz);
      me.heading = 0;
      me.slideX = me.slideZ = 0;
      camera.x = me.x;
      camera.z = me.z + PLAYER_CAMERA.ahead;
    }
    $("status").hidden = true;
    $("top").hidden = false;
  },
  tick(buffer) {
    world.applyTick(buffer);
  },
  you(message) {
    // The server did not accept a move. Go back to the position of the server.
    if (typeof message.x === "number") player.correct(message, performance.now());
  },
  records(list) {
    records = list;
  },
  record(record) {
    records = [record, ...records.filter((other) => other.id !== record.id)].sort((a, b) => b.id - a.id);
    // At a crossing, each player sees the record.
    if (record.first) showCard(record);
  },
  status(text) {
    $("status").hidden = text === "" && world.ready;
  },
});

player = new Player(world, guide, {
  move: (buffer) => net.move(buffer),
  lock: (cell, at) => net.lock(cell, at),
});

// ---------------------------------------------------------------------------
// The record of a bridge: signs, numbers and names

function count(name, value) {
  const element = document.createElement("span");
  element.className = "count";
  element.append(`${value}`, sign(name));
  return element;
}

function recordElement(record) {
  const element = document.createElement("div");
  element.className = "record";
  if (record.names.some((entry) => entry.name === me.name && !entry.helper)) element.classList.add("mine");

  const head = document.createElement("div");
  head.className = "head";
  const river = document.createElement("span");
  river.className = "river";
  river.append(sign("river"), `${record.id}`);
  const bodies = document.createElement("span");
  bodies.append(`${record.bodies}`, sign("body"));
  const time = document.createElement("span");
  time.append(`${record.seconds}`, sign("clock"));
  const left = document.createElement("span");
  left.className = "left";
  const size = document.createElement("small");
  size.textContent = `/ ${record.size}`;
  left.append(sign("food"), `${record.left}`, size);
  head.append(river, bodies, time, left);

  const names = document.createElement("ul");
  for (const entry of record.names) {
    const item = document.createElement("li");
    if (entry.helper) item.className = "helper";
    else if (entry.name === me.name) item.className = "me";
    const dot = document.createElement("i");
    dot.className = "dot";
    dot.style.background = cssColor(entry.helper ? HELPER_COLOR : colorOf(entry.name));
    const who = document.createElement("span");
    who.className = "who";
    who.textContent = entry.name;
    item.append(dot, who, count("body", entry.bodies), count("food", entry.food));
    names.appendChild(item);
  }
  element.append(head, names);
  return element;
}

let cardTimer = null;
function showCard(record) {
  $("card").replaceChildren(recordElement(record));
  $("card").hidden = false;
  clearTimeout(cardTimer);
  cardTimer = setTimeout(() => ($("card").hidden = true), 6000);
}

// ---------------------------------------------------------------------------
// Input

let selected = -1;
let selectedTime = 0;
let selectedData = null;

const input = new Input(
  { zone: $("zone"), stick: $("stick"), knob: $("knob"), lock: $("lock"), canvas },
  {
    lock() {
      if (look) return;
      const button = $("lock");
      button.classList.add("tap");
      setTimeout(() => button.classList.remove("tap"), 90);
      player.lock(performance.now(), () => performance.now()).then((result) => {
        if (result === "spare") noSpare();
        else if (result) locked(result);
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

// The colony has no spare body: the button shakes and the number at the top flashes.
function noSpare() {
  const button = $("lock");
  button.classList.remove("no");
  void button.offsetWidth;
  button.classList.add("no");
}

// This player locked: the picture of the body goes to the new body.
function locked(result) {
  me.slideX = result.from[0] - result.to[0];
  me.slideZ = result.from[1] - result.to[1];
}

// ---------------------------------------------------------------------------
// The marks: the open cells, the cell for a lock, and the body of this player

const rings = new Float32Array(MESH_STRIDE * 4);
const cells = new Float32Array(MESH_STRIDE * 2);
let openMarks = new Float32Array(MESH_STRIDE * 64);

function put(list, index, x, y, z, turn, size, color, alpha) {
  list.set([x, y, z, turn, size, 1, size, color[0], color[1], color[2], alpha], index * MESH_STRIDE);
}

function markCells(time, now) {
  const grid = world.grid;
  let ringCount = 0;
  let cellCount = 0;
  let openCount = 0;

  // Each open cell on the screen has a bright edge that moves slowly, all the time.
  if (world.open.size * MESH_STRIDE > openMarks.length) openMarks = new Float32Array(world.open.size * MESH_STRIDE * 2);
  const spare = world.freeWorkers > 0;
  for (const cell of world.open) {
    const x = grid.x(cell);
    const z = grid.z(cell);
    if (!renderer.sees(x, z)) continue;
    // With no spare body, a lock is not possible: the edge is weak.
    put(openMarks, openCount++, x, 0.03, z, 0, 1, [1, 0.86, 0.35], spare ? 0.95 : 0.35);
  }

  if (me.alive) {
    // A ring on the ground shows the body of this player between the workers.
    put(rings, ringCount++, me.x + me.slideX, me.y + 0.04, me.z + me.slideZ, time * 0.8, 0.82, [1, 1, 1], 0.55);
    const target = player.target;
    if (target >= 0 && spare) {
      const pulse = 0.5 + 0.5 * Math.sin(time * 6);
      const ready = player.ready(now);
      put(cells, cellCount++, grid.x(target), 0.025, grid.z(target), 0, 1, [1, 0.86, 0.3], ready ? 0.4 + 0.25 * pulse : 0.2);
      put(rings, ringCount++, grid.x(target), 0.035, grid.z(target), 0, 1, [1, 1, 0.9], ready ? 1 : 0.5);
    }
  }
  renderer.fill("open", openMarks, openCount);
  renderer.fill("rings", rings, ringCount);
  renderer.fill("cells", cells, cellCount);
  $("lock").classList.toggle("ready", player.ready(now));
}

// ---------------------------------------------------------------------------
// The camera

const camera = { x: 30, z: 5, ...PLAYER_CAMERA };

function moveCamera(dt, time) {
  const grid = world.grid;
  if (look) {
    // A slow camera goes along the world, from the nest to the north and back.
    const north = world.stage <= grid.rivers.length ? grid.rivers[world.stage - 1].start + 8 : grid.rows - 4;
    const part = 0.5 - 0.5 * Math.cos(time * 0.05);
    const follow = 1 - Math.exp(-dt * 0.6);
    camera.x += (grid.x(world.nest) + Math.sin(time * 0.07) * 6 - camera.x) * follow;
    camera.z += (4 + part * (north * 0.866 - 4) - camera.z) * follow;
    camera.turn = 0.25 * Math.sin(time * 0.09);
    const far = canvas.clientWidth < canvas.clientHeight ? 1.5 : 1;
    camera.height = 8.2 * far;
    camera.distance = 9 * far;
  } else {
    // The camera follows the body softly.
    const follow = 1 - Math.exp(-dt * 6);
    camera.x += (me.x - camera.x) * follow;
    camera.z += (me.z + PLAYER_CAMERA.ahead - camera.z) * follow;
  }
  renderer.setCamera(camera);
}

// ---------------------------------------------------------------------------
// The arrow at the edge of the screen

// What the arrow shows now: { goal, x, y, angle } on the page, or null. A test reads it.
let arrow = null;

function moveArrow() {
  arrow = guide.arrow(me, (x, y, z) => renderer.project(x, y, z), canvas.clientWidth, canvas.clientHeight);
  const element = $("arrow");
  element.hidden = !arrow;
  if (arrow) {
    element.style.left = `${arrow.x}px`;
    element.style.top = `${arrow.y}px`;
    $("arrowPoint").style.rotate = `${Math.atan2(arrow.dx, -arrow.dy)}rad`;
    if (element.dataset.goal !== arrow.goal) {
      element.dataset.goal = arrow.goal;
      $("arrowPoint").innerHTML = SIGNS.arrow;
      $("arrowGoal").innerHTML = SIGNS[{ open: "cell", pile: "food", nest: "nest" }[arrow.goal]];
    }
  }
}

// ---------------------------------------------------------------------------
// Names and numbers above the picture

const labels = new Map();
const pileLabels = new Map();

function drawLabels() {
  for (const [id, other] of world.players) {
    if (id === world.you) continue;
    let label = labels.get(id);
    if (!label) {
      label = document.createElement("div");
      $("labels").appendChild(label);
      labels.set(id, label);
    }
    const at = renderer.project(other.x, other.y + 0.55, other.z);
    label.hidden = !at;
    if (at) {
      label.textContent = other.name;
      label.className = other.helper ? "helper" : "";
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

  // The number of units of each pile, above the pile. The number is red while the pile
  // loses units.
  for (const pile of world.piles.values()) {
    let label = pileLabels.get(pile.id);
    if (!label) {
      label = document.createElement("div");
      label.append(sign("food"), document.createElement("span"));
      $("labels").appendChild(label);
      pileLabels.set(pile.id, label);
    }
    const at = pile.units > 0 ? renderer.project(world.grid.x(pile.cell), 1.6, world.grid.z(pile.cell)) : null;
    label.hidden = !at;
    if (at) {
      label.className = pile.far && world.time - pile.changed < 2.5 ? "pile loss" : "pile";
      label.lastChild.textContent = `${pile.units}`;
      label.style.left = `${at[0]}px`;
      label.style.top = `${at[1]}px`;
    }
  }
  for (const [id, label] of pileLabels) {
    if (!world.piles.has(id)) {
      label.remove();
      pileLabels.delete(id);
    }
  }

  // A mark above the body of this player.
  const mark = me.alive ? renderer.project(me.x + me.slideX, me.y + 0.62, me.z + me.slideZ) : null;
  $("you").hidden = !mark;
  if (mark) {
    $("you").style.left = `${mark[0]}px`;
    $("you").style.top = `${mark[1]}px`;
  }

  // The name, the time and the count of the locked body that the player tapped.
  const info = $("info");
  const body = selected >= 0 ? world.locked.get(selected) : null;
  const at = body && performance.now() - selectedTime < 6000 ? renderer.project(body.x, 0.3, body.z) : null;
  info.hidden = !at;
  if (at) {
    if (info.dataset.cell !== `${selected}:${selectedData ? 1 : 0}`) {
      info.dataset.cell = `${selected}:${selectedData ? 1 : 0}`;
      const when = new Date(body.time * 1000);
      info.replaceChildren();
      info.appendChild(document.createElement("b")).textContent = body.name;
      const time = document.createElement("span");
      time.append(sign("clock"), `${when.toLocaleDateString()} ${when.toLocaleTimeString()}`);
      info.append(time);
      if (selectedData) {
        const steps = document.createElement("span");
        steps.append(sign("steps"), `${selectedData.crossings}`);
        info.append(steps);
      }
    }
    info.style.left = `${at[0]}px`;
    info.style.top = `${at[1]}px`;
  }
}

// The numbers at the top: the spare bodies and the food at the nest.
let shownSpare = -1;
let shownFood = -1;

function again(element, name) {
  element.classList.remove(name);
  void element.offsetWidth;
  element.classList.add(name);
}

function drawCounts() {
  const spare = world.freeWorkers;
  if (spare !== shownSpare) {
    // The number moves a little when a lock uses a spare body.
    if (spare < shownSpare) again($("spare"), "used");
    shownSpare = spare;
    $("spareCount").textContent = `${spare}`;
    $("spare").classList.toggle("low", spare > 0 && spare < 5);
    $("spare").classList.toggle("none", spare === 0);
  }
  if (world.foodNest !== shownFood) {
    if (shownFood >= 0 && world.foodNest > shownFood) again($("food"), "more");
    if (firstFood === null && world.foodNest > 0 && shownFood >= 0) firstFood = performance.now();
    shownFood = world.foodNest;
    $("foodCount").textContent = `${world.foodNest}`;
  }
}

// ---------------------------------------------------------------------------
// Statistics, and the number of pixels

let frames = 0;
let slowTime = 0;
let frameTime = 0;
let lastSecond = performance.now();
function everySecond(now) {
  const seconds = (now - lastSecond) / 1000;
  const fps = frames / seconds;
  const bytes = net.takeBytes() / seconds;
  if (showStats) {
    $("stats").hidden = false;
    $("stats").textContent =
      `frames each second  ${fps.toFixed(0)}\n` +
      `frame time          ${frameTime.toFixed(1)} ms\n` +
      `bodies              ${world.bodyTotal()}\n` +
      `delay to server     ${net.delay.toFixed(0)} ms\n` +
      `bytes each second   ${Math.round(bytes)}\n` +
      `pixels              ${renderer.scale.toFixed(2)}`;
    net.ping();
  }
  frames = 0;
  lastSecond = now;
}

// If a frame takes more than 20 milliseconds for 2 seconds, the page uses fewer pixels.
function watchSpeed(dt) {
  frameTime += (dt * 1000 - frameTime) * 0.1;
  if (fixedScale || !world.ready) return;
  slowTime = frameTime > 20 ? slowTime + dt : 0;
  if (slowTime >= 2 && renderer.scale > 0.75) {
    renderer.scale = Math.max(0.75, renderer.scale * 0.8);
    slowTime = 0;
  }
}

// ---------------------------------------------------------------------------
// Each frame

let solidKey = -1;
let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  // A slow frame does not make the game slow: the time of the frame is the real time.
  const dt = Math.min(0.25, (now - last) / 1000);
  last = now;
  frames++;
  watchSpeed(dt);
  if (now - lastSecond >= 1000) everySecond(now);
  renderer.resize();

  if (world.ready) {
    const time = world.time;
    if (!look) {
      player.step(dt, input.x, input.y);
      player.send(now);
    }
    world.update(dt);
    world.takeNews();
    markCells(time, now);
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
    if (solidKey !== world.structure) {
      renderer.setSolid(world);
      solidKey = world.structure;
    }
    renderer.draw(world, time);
    moveArrow();
    drawLabels();
    drawCounts();
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
  guide,
  player,
  input,
  records: () => records,
  arrow: () => arrow,
  times: () => ({ load: loadTime, firstFood }),
  // What a person sees: the button, the body, the open cells on the screen and the arrow.
  view() {
    if (!world.ready) return { lock: false, me: null, open: [], arrow: null };
    const ready = $("lock").classList.contains("ready");
    return guide.view(me, ready, arrow, (x, y, z) => renderer.project(x, y, z), canvas.clientWidth, canvas.clientHeight);
  },
};
