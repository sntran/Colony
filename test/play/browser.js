// Helpers for the play tests: a browser page of the game with real touch events and real
// key events, and a player that reads the state of the page to decide where to go.

const { chromium } = require("playwright");

const BASE = process.env.COLONY_URL || "http://localhost:4000/";
// The software renderer of a machine with no graphics card is slow. These flags start it.
const ARGS = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"];
const STICK = { x: 90, y: 740, radius: 46 };
const LOCK = { x: 326, y: 758 };
const SCENT = { x: 237, y: 785 };

async function launch() {
  return chromium.launch({ args: ARGS });
}

// kind: "phone" (390 x 844, touch) or "desk" (1280 x 800, keys).
async function open(browser, kind, query = "") {
  const phone = kind === "phone";
  const context = await browser.newContext(
    phone
      ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true }
      : { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2 }
  );
  const page = await context.newPage();
  const errors = [];
  page.on("console", (message) => message.type() === "error" && errors.push(message.text()));
  page.on("pageerror", (error) => errors.push(error.message));
  // A small canvas keeps the software renderer fast. A screenshot uses the full size.
  await page.goto(`${BASE}?scale=0.5${query}`);
  await page.waitForFunction(() => window.colony && window.colony.world.ready);
  const cdp = await context.newCDPSession(page);

  // Real touch events through the browser. More than one finger can be down.
  const fingers = new Map();
  const points = () => [...fingers].map(([id, p]) => ({ id, x: p.x, y: p.y }));
  const touch = {
    async down(id, x, y) {
      fingers.set(id, { x, y });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: points() });
    },
    async move(id, x, y) {
      fingers.set(id, { x, y });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: points() });
    },
    async up(id) {
      fingers.delete(id);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: points() });
    },
    async tap(id, x, y) {
      await touch.down(id, x, y);
      await page.waitForTimeout(70);
      await touch.up(id);
    },
  };

  // The state of the game as the page has it.
  const state = () =>
    page.evaluate(() => {
      const { world } = window.colony;
      const grid = world.grid;
      const cell = grid.cellAt(world.me.x, world.me.z);
      const locked = {};
      for (const [id, body] of world.locked) locked[id] = { kind: body.kind, name: body.name, support: body.support, time: body.time };
      let scent = 0;
      for (const value of world.scent) if (value > 0) scent++;
      return {
        x: world.me.x, z: world.me.z, heading: world.me.heading, alive: world.me.alive, cell,
        name: world.me.name, locked, frontier: [...world.frontier], target: window.colony.target(),
        foodNest: world.foodNest, foodPile: world.foodPile, scent, tick: world.tick,
        workers: world.freeWorkers, players: world.players.size,
        grid: { width: grid.width, nearRows: grid.nearRows, gapRows: grid.gapRows, farRows: grid.farRows },
        nest: world.nest, food: world.food,
        banner: document.getElementById("banner").hidden ? "" : document.getElementById("banner").textContent,
        lockReady: document.getElementById("lock").classList.contains("ready"),
      };
    });

  // A screenshot with all the pixels, as a person sees the page on a good screen.
  const shot = async (path) => {
    await page.evaluate(() => (window.colony.renderer.scale = 2));
    await page.waitForTimeout(700);
    await page.screenshot({ path, type: "jpeg", quality: 80 });
    await page.evaluate(() => (window.colony.renderer.scale = 0.5));
  };

  return { context, page, touch, state, shot, errors, kind };
}

// ---------------------------------------------------------------------------
// The grid, as in priv/static/js/hex.js.

const ROW_STEP = Math.sqrt(3) / 2;

function gridOf({ width, nearRows, gapRows, farRows }) {
  const rows = nearRows + gapRows + farRows;
  const row = (cell) => Math.floor(cell / width);
  const kind = (cell) => (row(cell) < nearRows ? "near" : row(cell) < nearRows + gapRows ? "gap" : "far");
  const neighbors = (cell) => {
    const r = row(cell);
    const c = cell % width;
    const shift = r & 1;
    return [[r, c + 1], [r, c - 1], [r + 1, c + shift], [r + 1, c + shift - 1], [r - 1, c + shift], [r - 1, c + shift - 1]]
      .filter(([nr, nc]) => nr >= 0 && nr < rows && nc >= 0 && nc < width)
      .map(([nr, nc]) => nr * width + nc);
  };
  const center = (cell) => [(cell % width) + 0.5 * (row(cell) & 1), row(cell) * ROW_STEP];
  return { width, rows, row, kind, neighbors, center, cell: (r, c) => r * width + c };
}

// The number of steps on foot from a cell to each cell that a body can get to.
function reach(grid, locked, from) {
  const steps = new Map([[from, 0]]);
  const before = new Map();
  let front = [from];
  while (front.length) {
    const next = [];
    for (const cell of front) {
      for (const to of grid.neighbors(cell)) {
        if (steps.has(to) || (grid.kind(to) === "gap" && !(to in locked))) continue;
        steps.set(to, steps.get(cell) + 1);
        before.set(to, cell);
        next.push(to);
      }
    }
    front = next;
  }
  const path = (to) => {
    const cells = [];
    for (let cell = to; cell !== from; cell = before.get(cell)) cells.unshift(cell);
    return cells;
  };
  return { steps, path };
}

// ---------------------------------------------------------------------------
// A player. It moves the body with the stick (touch) or with the keys.

function player(session) {
  const { page, touch, state, kind } = session;
  let keys = new Set();
  let stick = false;

  // Pushes the stick, or holds the keys, in a direction of the world.
  // On the screen, right is the -x direction of the world and up is the +z direction.
  async function push(dx, dz, strength = 1) {
    const length = Math.hypot(dx, dz) || 1;
    if (kind === "phone") {
      if (!stick) {
        await touch.down(1, STICK.x, STICK.y);
        stick = true;
      }
      await touch.move(1, STICK.x + (-dx / length) * STICK.radius * strength, STICK.y - (dz / length) * STICK.radius * strength);
    } else {
      const want = new Set();
      if (dz / length > 0.38) want.add("KeyW");
      if (dz / length < -0.38) want.add("KeyS");
      if (dx / length > 0.38) want.add("KeyA");
      if (dx / length < -0.38) want.add("KeyD");
      for (const key of keys) if (!want.has(key)) await page.keyboard.up(key);
      for (const key of want) if (!keys.has(key)) await page.keyboard.down(key);
      keys = want;
    }
  }

  async function release() {
    if (stick) await touch.up(1);
    stick = false;
    for (const key of keys) await page.keyboard.up(key);
    keys = new Set();
  }

  // Goes to a point. Returns false if the body does not get there in time.
  async function goTo(x, z, tolerance = 0.2, limit = 15000, slow = true) {
    const end = Date.now() + limit;
    while (Date.now() < end) {
      const now = await state();
      if (!now.alive) {
        await release();
        return false;
      }
      const dx = x - now.x;
      const dz = z - now.z;
      const distance = Math.hypot(dx, dz);
      if (distance < tolerance) {
        await release();
        return true;
      }
      await push(dx, dz, !slow || distance > 1 ? 1 : Math.max(0.35, distance));
      await page.waitForTimeout(kind === "phone" ? 40 : 60);
    }
    await release();
    return false;
  }

  // Goes along the cells to a cell.
  async function walk(target) {
    const now = await state();
    const grid = gridOf(now.grid);
    const { steps, path } = reach(grid, now.locked, now.cell);
    if (!steps.has(target)) return false;
    const cells = path(target);
    for (let i = 0; i < cells.length; i++) {
      const [x, z] = grid.center(cells[i]);
      // The points between are not exact. The last point is.
      const last = i === cells.length - 1;
      if (!(await goTo(x, z, last ? 0.2 : 0.45, 15000, last))) return false;
    }
    return true;
  }

  async function waitAlive() {
    await page.waitForFunction(() => window.colony.world.me.alive, null, { timeout: 10000 });
  }

  // Looks at a cell, then locks into it. The page selects the cell in the direction of the body.
  async function lock(cell) {
    const grid = gridOf((await state()).grid);
    const [x, z] = grid.center(cell);
    for (let attempt = 0; attempt < 12; attempt++) {
      const now = await state();
      if (now.target === cell) break;
      // A small push of the stick, or a short press of the keys, turns the body to the cell.
      await push(x - now.x, z - now.z, 0.5);
      await page.waitForTimeout(kind === "phone" ? 120 : 50);
      if (kind !== "phone") {
        await release();
        await page.waitForTimeout(150);
      }
    }
    await release();
    const now = await state();
    if (now.target !== cell) return false;
    if (kind === "phone") await touch.tap(2, LOCK.x, LOCK.y);
    else await page.keyboard.press("Space");
    try {
      await page.waitForFunction((id) => window.colony.world.locked.has(id), cell, { timeout: 4000 });
      return true;
    } catch (_) {
      return false;
    }
  }

  async function scent(on) {
    if (kind === "phone") {
      if (on) await touch.down(3, SCENT.x, SCENT.y);
      else await touch.up(3);
    } else if (on) await page.keyboard.down("Shift");
    else await page.keyboard.up("Shift");
  }

  return { push, release, goTo, walk, lock, scent, waitAlive };
}

module.exports = { launch, open, player, gridOf, reach };
