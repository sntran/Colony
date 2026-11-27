// The page: it connects the server, the input, the picture and the sound.

import { ROW_STEP } from "./hex.js";
import { Net } from "./net.js";
import { World, MESH_STRIDE } from "./state.js";
import { Renderer, PILE_LIGHT_DELAY } from "./render.js";
import { Input } from "./input.js";
import { Guide } from "./guide.js";
import { Player } from "./player.js";
import { Sound } from "./sound.js";
import { Story } from "./story.js";
import { Effects } from "./fx.js";
import { PLAYER_CAMERA } from "./view.js";
import { myName, newName, colorOf, cssColor, HELPER_COLOR } from "./names.js";
import { SIGNS, putSigns, sign } from "./signs.js";

const params = new URLSearchParams(location.search);
// "?story=1" shows the story with no body in the world. "?demo=1" shows the story one
// time, then the live world with a slow camera. These pages only look.
const storyPage = params.get("story") === "1";
const demoPage = params.get("demo") === "1";
const look = storyPage || demoPage;
const showStats = params.get("stats") === "1";
// "?scale=1" sets the number of canvas pixels for each page pixel and stops the automatic change.
const fixedScale = parseFloat(params.get("scale")) || 0;

const $ = (id) => document.getElementById(id);
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
const canvas = $("view");
const world = new World();
const me = world.me;
me.name = myName();
me.color = colorOf(me.name);
putSigns(document);

// If this browser cannot draw the game, the sign of the wait stays.
const renderer = new Renderer(canvas);
if (fixedScale) renderer.scale = fixedScale;
const fx = new Effects(renderer);
const sound = new Sound();

// The touch controls show on a device with a touch screen. The key help shows on the others.
const setTouch = () => {
  document.body.classList.remove("keys");
  document.body.classList.add("touch");
};
if (matchMedia("(pointer: coarse)").matches) setTouch();
window.addEventListener("touchstart", setTouch, { once: true, passive: true });
if (look) document.body.classList.add("look");

// The sound starts at the first touch or at the first key.
for (const event of ["pointerdown", "keydown"]) window.addEventListener(event, () => sound.start(), { capture: true, passive: true });

function showName() {
  $("name").textContent = me.name;
  $("swatch").style.background = cssColor(me.color);
}
showName();

// ---------------------------------------------------------------------------
// Messages from the server

let seed = null;
// The records of the bridges, the newest first.
let records = [];
// The time of the load of the page, and the time of the first food at the nest. A test reads them.
const loadTime = performance.now();
let firstFood = null;
// The grid that the renderer has: it changes when the server sends more rivers.
let gridKey = -1;

const guide = new Guide(world);
let player;

const net = new Net(me.name, look, {
  snapshot(buffer) {
    world.snapshot(buffer);
    if (seed !== world.seed || gridKey !== world.gridKey) {
      seed = world.seed;
      gridKey = world.gridKey;
      renderer.setWorld(world);
    }
    world.scentDirty = true;
    world.foodDirty = true;
    solidKey = "";
    const mine = world.players.get(world.you);
    me.alive = Boolean(mine);
    if (mine) {
      player.place(mine.tx, mine.tz);
      me.heading = 0;
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
    if (record.first) crossing(record);
    else if (story.phase === "end") showStory();
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

function nameItem(entry) {
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
  return item;
}

function small(text) {
  const element = document.createElement("small");
  element.textContent = text;
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
  // The bodies of the bridge, and the bodies of the best bridge for its widest column.
  bodies.append(`${record.bodies}`, ...(record.best ? [small(`/ ${record.best}`)] : []), sign("body"));
  const time = document.createElement("span");
  time.append(`${record.seconds}`, sign("clock"));
  // The food that was left in the pile at the crossing, of the food at its start.
  const left = document.createElement("span");
  left.className = "left";
  const size = document.createElement("small");
  size.textContent = `/ ${record.size}`;
  left.append(sign("food"), `${record.left}`, size);
  head.append(river, bodies, time, left);

  const names = document.createElement("ul");
  for (const entry of record.names) names.appendChild(nameItem(entry));
  element.append(head, names);
  return element;
}

let cardTimer = null;
function showCard(record) {
  if (story.running) return;
  $("card").replaceChildren(recordElement(record));
  $("card").hidden = false;
  clearTimeout(cardTimer);
  cardTimer = setTimeout(() => ($("card").hidden = true), 6000);
}

// ---------------------------------------------------------------------------
// The moment of a crossing

// While the camera shows the full bridge: { record, start, x, z, scale, stick }.
let showing = null;
// The number of crossings that this page showed. A test reads it.
let crossingsShown = 0;

function crossing(record) {
  crossingsShown++;
  // The story has a new part: its button flashes for some seconds.
  again($("storyButton"), "news");
  const bodies = [...world.locked.values()].filter((body) => body.river === record.id).sort((a, b) => a.n - b.n);
  // The song of the bridge: its notes again, fast, in the order of the locks. Then a chord.
  const center = bodies.length > 0 ? bodies[Math.floor(bodies.length / 2)] : null;
  const far = center ? Math.hypot(center.x - camera.x, center.z - camera.z) : 0;
  sound.song(record.id, bodies.map((body) => body.row), clamp(1.2 - far / 60, 0.35, 1));

  const mine = record.names.some((entry) => entry.name === me.name && !entry.helper);
  if (look || story.running || bodies.length === 0 || (!mine && far > 40)) {
    showCard(record);
    return;
  }
  // The camera moves back and shows the full bridge for 2.5 seconds.
  let [x0, x1, z0, z1] = [Infinity, -Infinity, Infinity, -Infinity];
  for (const body of bodies) {
    x0 = Math.min(x0, body.x);
    x1 = Math.max(x1, body.x);
    z0 = Math.min(z0, body.z);
    z1 = Math.max(z1, body.z);
  }
  const aspect = canvas.clientWidth / canvas.clientHeight;
  const scale = clamp(Math.max((z1 - z0 + 7) / 11, (x1 - x0 + 5) / (9 * aspect)), 1.15, 3);
  showing = { record, start: performance.now(), x: (x0 + x1) / 2, z: (z0 + z1) / 2 + 0.5, scale, stick: [input.x, input.y] };
}

function moveCrossing(now) {
  if (!showing) return;
  const time = now - showing.start;
  // A move of the stick stops this. The first moment does not count: the thumb is on
  // the stick at the lock.
  const moved = Math.hypot(input.x - showing.stick[0], input.y - showing.stick[1]) > 0.35;
  if (time < 300) showing.stick = [input.x, input.y];
  if (time > 2500 || (time >= 300 && moved)) {
    // The record card shows. Then the light of the next pile appears.
    showCard(showing.record);
    showing = null;
  }
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
      if (look || story.running) return;
      const element = $("lock");
      element.classList.add("tap");
      setTimeout(() => element.classList.remove("tap"), 90);
      player.lock(performance.now(), () => performance.now()).then((result) => {
        if (result === "spare") noSpare();
        else if (result === "carry") again($("lock"), "no");
        else if (result) locked(result);
      });
    },
    tap(x, y) {
      // Show the name, the time and the count of a locked body.
      if (!world.ready || story.running) return;
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

function again(element, name) {
  element.classList.remove(name);
  void element.offsetWidth;
  element.classList.add(name);
}

// The colony has no spare body: a low sound, the button shakes, and the number at the
// top flashes.
function noSpare() {
  sound.none();
  again($("lock"), "no");
}

// The locks of this player that had their note. The news of such a lock makes no
// second note.
const mine = new Set();
// The light that flies from the locked body of this player to the new body.
let flight = null;

function vibrate() {
  try {
    if (navigator.vibrate) navigator.vibrate(15);
  } catch (_) {
    // This browser does not shake the phone.
  }
}

// The moment of a lock of this player. In this order, in less than half a second: the
// body goes down into the cell, a note plays and the phone shakes, a point of light
// flies to the new body and the camera follows it, and the name shows.
function locked(result) {
  const grid = world.grid;
  if (!mine.delete(`heard:${result.cell}`)) {
    sound.lock(grid.river(result.cell), grid.riverRow(result.cell), 1);
    mine.add(result.cell);
  }
  vibrate();
  me.slideX = me.slideZ = 0;
  me.arrive = world.time + 0.4;
  flight = fx.light([grid.x(result.cell), grid.z(result.cell)], result.to, me.color, world.time, 0.4);
}

// A tap on my name gives a new random name. The name stays on this device.
$("me").addEventListener("pointerup", () => {
  if (look) return;
  me.name = newName();
  me.color = colorOf(me.name);
  showName();
  net.rename(me.name);
});

function showSound() {
  $("soundButton").innerHTML = sound.on ? SIGNS.soundOn : SIGNS.soundOff;
}
showSound();
$("soundButton").addEventListener("pointerup", () => {
  sound.start();
  sound.toggle();
  showSound();
});

// ---------------------------------------------------------------------------
// What the last messages brought: locks, new workers and food

// The names of the bodies that locked a moment before: { cell, name, helper, until }.
let lockNames = [];
let stepAt = 0;

function takeNews(now) {
  const news = world.takeNews();
  if (!world.ready) return;
  const grid = world.grid;
  for (const lock of news.locks) {
    const x = grid.x(lock.cell);
    const z = grid.z(lock.cell);
    // A ring goes out on the water when the body is down.
    fx.ripple(x, z, world.time + 0.13);
    // The name label of the locked body shows for 2 seconds.
    lockNames.push({ cell: lock.cell, name: lock.name, helper: lock.helper, until: now + 2000 });
    if (lockNames.length > 8) lockNames.shift();
    if (mine.delete(lock.cell)) continue;
    const near = lock.id === world.you ? 1 : clamp(1 - Math.hypot(x - camera.x, z - camera.z) / 34, 0.1, 0.75);
    sound.lock(grid.river(lock.cell), grid.riverRow(lock.cell), near);
    if (lock.id === world.you) {
      // The message of the lock came before its reply.
      mine.add(`heard:${lock.cell}`);
    } else {
      // The light of an other player flies to the new body of that player.
      const other = world.players.get(lock.id);
      if (other && renderer.sees(x, z)) fx.light([x, z], [other.tx, other.tz], other.color, world.time, 0.4);
    }
  }
  const nest = [grid.x(world.nest), grid.z(world.nest)];
  const near = clamp(1 - Math.hypot(nest[0] - camera.x, nest[1] - camera.z) / 22, 0, 1);
  for (let i = 0; i < Math.min(2, news.food); i++) sound.food(near);
  if (news.workers > 0) sound.worker(near);

  // The steps of this body: very soft ticks.
  if (player.walked - stepAt > 0.62) {
    stepAt = player.walked;
    sound.step();
  }
  // Water: louder near a river.
  let distance = Infinity;
  const z = look ? camera.z : me.z;
  for (const river of grid.rivers) {
    const south = river.start * ROW_STEP - 0.5;
    const north = (river.start + Math.max(...river.widths)) * ROW_STEP;
    distance = Math.min(distance, Math.max(0, south - z, z - north));
  }
  sound.setWater(clamp(1 - distance / 7, 0.08, 1));
}

// ---------------------------------------------------------------------------
// The marks: the open cells, the cell for a lock, and the body of this player

const rings = new Float32Array(MESH_STRIDE * 4);
const guideMarks = new Float32Array(MESH_STRIDE * 2);
const cells = new Float32Array(MESH_STRIDE * 2);
let openMarks = new Float32Array(MESH_STRIDE * 64);

function put(list, index, x, y, z, turn, size, color, alpha) {
  list.set([x, y, z, turn, size, 1, size, color[0], color[1], color[2], alpha], index * MESH_STRIDE);
}

// The state of the button: the first state that applies.
//   "food": I carry food. "none": the colony has no spare body. "rest": my new body rests.
//   "lock": a lock is possible. "wait": the guide has no target. "dim": my cell does not
//   touch an open cell.
let button = "dim";

function buttonState(now) {
  if (look || story.running) return "dim";
  return player.button(now);
}

const BUTTON_SIGNS = {
  food: SIGNS.food,
  none: `${SIGNS.body}<b>0</b>`,
  rest: `<svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="16" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="5"/><circle id="restRing" cx="20" cy="20" r="16" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" stroke-dasharray="100.5" stroke-dashoffset="100.5" transform="rotate(-90 20 20)"/></svg>`,
  lock: SIGNS.lock,
  wait: SIGNS.wait,
  dim: SIGNS.lock,
};

function showButton(now) {
  const state = buttonState(now);
  const element = $("lock");
  if (state !== button) {
    button = state;
    element.className = `state-${state}`;
    element.innerHTML = BUTTON_SIGNS[state];
  }
  if (state === "rest") {
    // The ring fills in 1 second.
    const part = Math.max(0, Math.min(1, 1 - (player.restUntil - now) / 1000));
    const ring = document.getElementById("restRing");
    if (ring) ring.setAttribute("stroke-dashoffset", `${100.5 * (1 - part)}`);
  }
}

function markCells(time, now) {
  const grid = world.grid;
  let ringCount = 0;
  let cellCount = 0;
  let openCount = 0;
  let guideCount = 0;
  const marks = !story.running;

  // Each open cell on the screen has an edge that moves slowly, all the time. In the
  // "wider" phase, the cells with the largest gain are bright and the others are weak.
  // With no spare body, all the edges are weak and grey.
  if (world.open.size * MESH_STRIDE > openMarks.length) openMarks = new Float32Array(world.open.size * MESH_STRIDE * 2);
  const spare = world.spare > 0;
  for (const [cell, gain] of marks ? world.open : []) {
    const x = grid.x(cell);
    const z = grid.z(cell);
    if (!renderer.sees(x, z)) continue;
    if (!spare) put(openMarks, openCount++, x, 0.03, z, 0, 1, [0.78, 0.8, 0.8], 0.3);
    else if (gain >= world.openBest) put(openMarks, openCount++, x, 0.03, z, 0, 1, [1, 0.86, 0.35], 0.95);
    else put(openMarks, openCount++, x, 0.03, z, 0, 0.92, [1, 0.9, 0.6], 0.32);
  }

  if (me.alive && marks) {
    // A ring on the ground shows the body of this player between the workers.
    if (time >= me.arrive) put(rings, ringCount++, me.x, me.y + 0.04, me.z, time * 0.8, 0.82, [1, 1, 1], 0.55);
    const target = player.target;
    if (target >= 0 && spare && !me.carry) {
      const pulse = 0.5 + 0.5 * Math.sin(time * 6);
      const ready = player.ready(now);
      put(cells, cellCount++, grid.x(target), 0.025, grid.z(target), 0, 1, [1, 0.86, 0.3], ready ? 0.4 + 0.25 * pulse : 0.2);
      put(rings, ringCount++, grid.x(target), 0.035, grid.z(target), 0, 1, [1, 1, 0.9], ready ? 1 : 0.5);
    }
    // The mark of the guide: a ring in my color that moves, on the target.
    const guide = player.current;
    if (guide && time >= me.arrive) {
      const x = grid.x(guide.cell);
      const z = grid.z(guide.cell);
      const size = guide.kind === "open" ? 1.05 : 1.5;
      const beat = 0.5 + 0.5 * Math.sin(time * 4.5);
      put(guideMarks, guideCount++, x, 0.06, z, time * 1.3, size * (1 + 0.12 * beat), me.color, 0.95);
      put(guideMarks, guideCount++, x, 0.06, z, -time * 0.9, size * (1.32 + 0.1 * beat), me.color, 0.45);
    }
  }
  renderer.fill("open", openMarks, openCount);
  renderer.fill("rings", rings, ringCount);
  renderer.fill("cells", cells, cellCount);
  renderer.fill("guide", guideMarks, guideCount);
  showButton(now);
}

// ---------------------------------------------------------------------------
// The camera

const camera = { x: 30, z: 5, ...PLAYER_CAMERA };
// The camera looks a little in the direction of the move.
const lead = [0, 0];

function moveCamera(dt, time) {
  const grid = world.grid;
  let [height, distance, turn, fov] = [PLAYER_CAMERA.height, PLAYER_CAMERA.distance, 0, PLAYER_CAMERA.fov];
  let rate = 6;
  let x = camera.x;
  let z = camera.z;
  camera.far = 140;

  if (story.running) {
    story.update(dt, camera);
    renderer.setCamera(camera);
    return;
  }
  if (look) {
    // A slow camera goes along the world, from the nest to the north and back.
    const north = world.stage <= grid.rivers.length ? grid.rivers[world.stage - 1].start + 8 : grid.rows - 4;
    const part = 0.5 - 0.5 * Math.cos(time * 0.05);
    x = grid.x(world.nest) + Math.sin(time * 0.07) * 6;
    z = 4 + part * (north * ROW_STEP - 4);
    turn = 0.25 * Math.sin(time * 0.09);
    const tall = canvas.clientWidth < canvas.clientHeight ? 1.5 : 1;
    height = 8.2 * tall;
    distance = 9 * tall;
    rate = 0.6;
  } else if (showing) {
    // The camera moves back and shows the full bridge.
    x = showing.x;
    z = showing.z;
    height *= showing.scale;
    distance *= showing.scale;
    rate = 3.2;
  } else {
    // The camera follows the body softly.
    const moving = Math.hypot(input.x, input.y) > 0.1;
    const ease = 1 - Math.exp(-dt * 1.6);
    lead[0] += ((moving ? -input.x * 1.3 : 0) - lead[0]) * ease;
    lead[1] += ((moving ? input.y * 1.3 : 0) - lead[1]) * ease;
    x = me.x + lead[0];
    z = me.z + PLAYER_CAMERA.ahead + lead[1];
    // After a lock, the camera follows the light to the new body. Thus the player
    // always knows where the new body is.
    const at = flight ? fx.lightAt(flight, time) : null;
    if (at) {
      x = at[0];
      z = at[2] + PLAYER_CAMERA.ahead;
      rate = 14;
    } else {
      flight = null;
    }
  }
  const follow = 1 - Math.exp(-dt * rate);
  const slow = 1 - Math.exp(-dt * Math.min(rate, 3.5));
  camera.x += (x - camera.x) * follow;
  camera.z += (z - camera.z) * follow;
  camera.height += (height - camera.height) * slow;
  camera.distance += (distance - camera.distance) * slow;
  camera.turn += (turn - camera.turn) * slow;
  camera.fov += (fov - camera.fov) * slow;
  renderer.setCamera(camera);
}

// ---------------------------------------------------------------------------
// The arrow at the edge of the screen

// What the arrow shows now: { goal, x, y, dx, dy } on the page, or null. A test reads it.
let arrow = null;

function moveArrow() {
  arrow = showing || story.running || !me.alive || world.time < me.arrive ? null : guide.arrow(me, player.current, (x, y, z) => renderer.project(x, y, z), canvas.clientWidth, canvas.clientHeight);
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

// One label for each key. A label that is not used in a frame goes away.
const labels = new Map();
let labelFrame = 0;

function label(key, kind, x, y, z) {
  const at = renderer.project(x, y, z);
  if (!at) return null;
  let element = labels.get(key);
  if (!element) {
    element = document.createElement("div");
    $("labels").appendChild(element);
    labels.set(key, element);
  }
  if (element.className !== kind) element.className = kind;
  element.style.left = `${at[0]}px`;
  element.style.top = `${at[1]}px`;
  element.frame = labelFrame;
  return element;
}

function text(element, value) {
  if (element && element.textContent !== value) element.textContent = value;
}

function drawLabels(now) {
  labelFrame++;
  const grid = world.grid;
  const free = !world.hideFree;
  for (const [id, other] of free ? world.players : []) {
    if (id === world.you) continue;
    text(label(`p${id}`, other.helper ? "helper" : "", other.x, other.y + 0.55, other.z), other.name);
  }

  // The number of units of each pile, above the pile. The number is red while the pile
  // loses units.
  for (const pile of world.piles.values()) {
    if (pile.units === 0 || world.time - pile.born < PILE_LIGHT_DELAY) continue;
    const loss = pile.far && world.time - pile.changed < 2.5;
    const element = label(`f${pile.id}`, loss ? "pile loss" : "pile", grid.x(pile.cell), 1.6, grid.z(pile.cell));
    if (!element) continue;
    if (!element.firstChild) element.append(sign("food"), document.createElement("span"));
    text(element.lastChild, `${pile.units}`);
  }

  // An old nest is a mark with the number of its land.
  for (const old of world.oldNests) {
    const element = label(`n${old.cell}`, "oldnest", grid.x(old.cell), 0.4, grid.z(old.cell));
    if (!element) continue;
    if (!element.firstChild) element.append(sign("nest"), document.createElement("span"));
    text(element.lastChild, `${old.land}`);
  }

  // The name of a body that locked a moment before, for 2 seconds.
  lockNames = lockNames.filter((entry) => entry.until > now);
  for (const entry of story.running ? [] : lockNames) {
    const element = label(`l${entry.cell}`, entry.helper ? "locked helper" : "locked", grid.x(entry.cell), 0.5, grid.z(entry.cell));
    text(element, entry.name);
    if (element) element.style.opacity = clamp((entry.until - now) / 400, 0, 1);
  }
  // The story: the first body of each player shows the name.
  story.labels.forEach((entry, index) => {
    text(label(`s${index}:${entry.name}`, entry.helper ? "locked helper" : "locked", entry.x, 0.5, entry.z), entry.name);
  });

  for (const [key, element] of labels) {
    if (element.frame !== labelFrame) {
      element.remove();
      labels.delete(key);
    }
  }

  // A mark above the body of this player. It is not there while the light flies.
  const mark = me.alive && free && world.time >= me.arrive ? renderer.project(me.x, me.y + 0.62, me.z) : null;
  $("you").hidden = !mark;
  if (mark) {
    $("you").style.left = `${mark[0]}px`;
    $("you").style.top = `${mark[1]}px`;
  }

  // The name, the time and the count of the locked body that the player tapped.
  const info = $("info");
  const body = selected >= 0 ? world.locked.get(selected) : null;
  const at = body && now - selectedTime < 6000 ? renderer.project(body.x, 0.3, body.z) : null;
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

function drawCounts() {
  const spare = world.spare;
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
// The story

const story = new Story({ world, renderer, sound, net, canvas });
story.wave = (body) => fx.ripple(body.x, body.z, world.time + 0.13);
story.onChange = showStory;
let storyTimer = null;

function showStory() {
  const end = story.phase === "end";
  document.body.classList.toggle("story", story.running);
  $("storyTools").hidden = !story.running;
  $("storyCount").hidden = story.phase !== "play";
  $("storyEnd").hidden = !end;
  $("storySave").hidden = !end;
  $("storyAgain").hidden = !end;
  if (story.running) $("card").hidden = true;
  if (!end) return;

  // The world from above: the number of crossings, of bodies and of food, the date, the
  // names with their bodies and their food, and the records of the bridges.
  const head = $("storyHead");
  head.replaceChildren();
  const part = (name, value) => {
    const element = document.createElement("span");
    element.append(sign(name), value);
    head.append(element);
  };
  part("river", `${world.stage - 1}`);
  part("body", `${world.locked.size}`);
  part("food", `${world.foodNest}`);
  const date = document.createElement("span");
  date.className = "date";
  date.textContent = new Date(world.startTime * 1000).toLocaleDateString();
  head.append(date);
  $("storyNames").replaceChildren(...story.names.map(nameItem));
  $("storyRecords").replaceChildren(...[...records].sort((a, b) => a.id - b.id).map(recordElement));

  // The demo mode shows the story one time, then the live world with a slow camera.
  clearTimeout(storyTimer);
  if (demoPage) storyTimer = setTimeout(() => story.close(), 9000);
}

// Draws the world with a camera from above and with many pixels, for the picture. `scale`
// is the number of canvas pixels for each page pixel.
function drawPicture(view, scale) {
  const before = renderer.scale;
  renderer.scale = scale;
  renderer.resize();
  renderer.setCamera(view);
  buildPicture(world.time);
  renderer.draw(world, world.time);
  renderer.scale = before;
}

// Not "click": a tap of the right thumb is not a click while the left thumb is on the stick.
$("storyButton").addEventListener("pointerup", () => story.open());
// The first tap goes to the end of the story. The second tap closes it.
$("storyClose").addEventListener("pointerup", () => (story.phase === "play" ? story.skip() : story.close()));
$("storyAgain").addEventListener("pointerup", () => {
  story.close();
  story.open();
});
$("storySave").addEventListener("pointerup", () => story.save(drawPicture));

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

// Makes the lists of the bodies and gives them to the picture.
function buildPicture(time) {
  world.build((x, z) => renderer.sees(x, z));
  renderer.fill("bodies", world.bodies, world.bodyCount);
  renderer.fill("shadows", world.shadows, world.shadowCount);
  renderer.fill("crumbs", world.crumbs, world.crumbCount);
  renderer.fill("decks", world.decks, world.deckCount);
  fx.update(time);
}

let solidKey = "";
let opened = false;
// A test stops the time of the page for a screenshot of one moment.
let frozen = false;
let last = performance.now();
function frame(now) {
  requestAnimationFrame(frame);
  // A slow frame does not make the game slow: the time of the frame is the real time.
  const dt = frozen ? 0 : Math.min(0.25, (now - last) / 1000);
  last = now;
  frames++;
  watchSpeed(dt);
  if (now - lastSecond >= 1000) everySecond(now);
  renderer.resize();

  if (world.ready) {
    const time = world.time;
    if (!look) {
      // While the story plays, the body does not move.
      const play = !story.running;
      player.step(dt, play ? input.x : 0, play ? input.y : 0);
      player.send(now);
    }
    world.update(dt);
    takeNews(now);
    moveCrossing(now);
    markCells(time, now);
    moveCamera(dt, time);
    buildPicture(time);
    // The light of a new pile grows for some seconds.
    for (const pile of world.piles.values()) if (time - pile.born < PILE_LIGHT_DELAY + 2) world.foodDirty = true;
    // The server sent more rivers: the renderer makes the new parts of the world.
    if (gridKey !== world.gridKey) {
      gridKey = world.gridKey;
      renderer.setWorld(world);
      solidKey = "";
      world.scentDirty = true;
    }
    if (world.scentDirty) {
      renderer.setScent(world);
      world.scentDirty = false;
    }
    if (world.foodDirty) {
      renderer.setFood(world);
      world.foodDirty = false;
    }
    if (solidKey !== `${world.structure}:${world.storyLimit}`) {
      renderer.setSolid(world);
      solidKey = `${world.structure}:${world.storyLimit}`;
    }
    renderer.draw(world, time);
    moveArrow();
    drawLabels(now);
    drawCounts();
    if (story.phase === "play") text($("storyShown"), `${story.shown} / ${story.locks.length}`);
    // The pages that only look start with the story.
    if (look && !opened) {
      opened = true;
      story.open();
    }
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
  sound,
  story,
  fx,
  records: () => records,
  arrow: () => arrow,
  times: () => ({ load: loadTime, firstFood }),
  freeze: (on) => (frozen = on),
  // The moments that the page shows now.
  moment: () => ({ flight: flight !== null, showing: showing !== null, crossings: crossingsShown, card: !$("card").hidden, lockNames: lockNames.length, ripples: fx.ripples.length }),
  // The picture of the story as a data address, for a test.
  async picture() {
    const blob = await story.picture(drawPicture);
    const data = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.readAsDataURL(blob);
    });
    return { data, names: story.pictureNames, date: story.pictureDate };
  },
  // What a person sees: the button, the body, the mark of the guide and the arrow.
  view() {
    if (!world.ready) return { lock: false, button: "dim", me: null, mark: null, arrow: null };
    // The mark shows only when the light of a lock got to the new body.
    const guideNow = world.time >= me.arrive ? player.current : null;
    return guide.view(me, button, guideNow, arrow, (x, y, z) => renderer.project(x, y, z), canvas.clientWidth, canvas.clientHeight);
  },
  button: () => button,
};
