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
    // The event touchEnd has only the finger that goes up. The other fingers stay down.
    async up(id) {
      const finger = fingers.get(id);
      if (!finger) return;
      fingers.delete(id);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [{ id, x: finger.x, y: finger.y }] });
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
      for (const [id, body] of world.locked) locked[id] = { helper: body.helper, name: body.name, support: body.support, time: body.time };
      let scent = 0;
      for (const value of world.scent) if (value > 0) scent++;
      const players = [...world.players.values()].map((player) => ({ name: player.name, helper: player.helper }));
      const reach = window.colony.reach();
      return {
        x: world.me.x, z: world.me.z, heading: world.me.heading, alive: world.me.alive, cell,
        name: world.me.name, locked, target: window.colony.target(), resting: window.colony.resting(),
        options: window.colony.options().map(([cell, possible]) => ({ cell, possible })),
        reach: reach && { rows: reach.cells.length, bank: reach.bank >= 0, part: reach.part },
        foodNest: world.foodNest, pile: world.pile, scent, tick: world.tick,
        workers: world.freeWorkers, players, records: window.colony.records(),
        grid: { width: grid.width, nearRows: grid.nearRows, rows: grid.rows, river: [...grid.river] },
        nest: world.nest,
        corrections: window.colony.corrections(),
        refused: window.colony.refused(),
        banner: document.getElementById("banner").hidden ? "" : document.getElementById("banner").textContent,
        card: document.getElementById("card").hidden ? "" : document.getElementById("card").textContent,
        lockReady: document.getElementById("lock").classList.contains("ready"),
        stickHeld: document.getElementById("stick").classList.contains("held"),
        scentHeld: document.getElementById("scent").classList.contains("held"),
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

function gridOf({ width, nearRows, rows, river }) {
  const row = (cell) => Math.floor(cell / width);
  const col = (cell) => cell % width;
  const kind = (cell) => (row(cell) < nearRows ? "near" : row(cell) < nearRows + river[col(cell)] ? "gap" : "far");
  const neighbor = (cell, direction) => {
    const r = row(cell);
    const c = col(cell);
    const shift = r & 1;
    const [nr, nc] = [[r, c + 1], [r, c - 1], [r + 1, c + shift], [r + 1, c + shift - 1], [r - 1, c + shift], [r - 1, c + shift - 1]][direction];
    return nr >= 0 && nr < rows && nc >= 0 && nc < width ? nr * width + nc : -1;
  };
  const neighbors = (cell) => [0, 1, 2, 3, 4, 5].map((direction) => neighbor(cell, direction)).filter((next) => next >= 0);
  const center = (cell) => [col(cell) + 0.5 * (row(cell) & 1), row(cell) * ROW_STEP];
  // The cell in the next row with the same column number, and the cells beside a cell.
  const straight = (cell) => neighbor(cell, row(cell) & 1 ? 3 : 2);
  const beside = (cell) => [neighbor(cell, 1), neighbor(cell, 0)].filter((next) => next >= 0);
  const riverRow = (cell) => row(cell) - nearRows + 1;
  return { width, rows, river, row, col, kind, neighbor, neighbors, center, straight, beside, riverRow, cell: (r, c) => r * width + c };
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
//
// On a phone the player uses two thumbs: the left thumb stays on the stick while the
// right thumb taps Lock or holds Scent.

function player(session) {
  const { page, touch, state, kind } = session;
  let keys = new Set();
  let stick = false;
  let scentOn = false;

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

  // Puts the stick in the middle. The thumb stays on it.
  async function rest() {
    if (kind === "phone" && stick) await touch.move(1, STICK.x, STICK.y);
    for (const key of keys) await page.keyboard.up(key);
    keys = new Set();
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
        await rest();
        return false;
      }
      const dx = x - now.x;
      const dz = z - now.z;
      const distance = Math.hypot(dx, dz);
      if (distance < tolerance) {
        await rest();
        return true;
      }
      await push(dx, dz, !slow || distance > 1 ? 1 : Math.max(0.35, distance));
      await page.waitForTimeout(kind === "phone" ? 40 : 60);
    }
    await rest();
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
    await page.waitForFunction(() => window.colony.world.me.alive, null, { timeout: 15000 });
  }

  // Taps Lock with the right thumb, or presses Space. The left thumb stays where it is.
  // The right thumb cannot hold Scent and tap Lock at the same time: it lets Scent go,
  // taps Lock, and holds Scent again.
  async function tapLock() {
    const scented = scentOn;
    if (kind === "phone") {
      if (scented) await scent(false);
      await touch.tap(2, LOCK.x, LOCK.y);
      if (scented) await scent(true);
    } else {
      await page.keyboard.press("Space");
    }
  }

  // Pushes the stick a small distance in the direction of a cell. The page then selects
  // that cell, if a lock is possible there. Returns true if the button Lock is bright
  // for that cell.
  async function look(cell) {
    const grid = gridOf((await state()).grid);
    const [x, z] = grid.center(cell);
    for (let attempt = 0; attempt < 10; attempt++) {
      const now = await state();
      if (now.target === cell && now.lockReady) {
        await rest();
        return true;
      }
      await push(x - now.x, z - now.z, 0.5);
      await page.waitForTimeout(kind === "phone" ? 110 : 50);
      if (kind !== "phone") {
        await rest();
        await page.waitForTimeout(150);
      }
    }
    await rest();
    const now = await state();
    return now.target === cell && now.lockReady;
  }

  // Looks at a cell and locks into it. Returns true if the body is locked there.
  async function lock(cell) {
    if (!(await look(cell))) return false;
    await tapLock();
    try {
      await page.waitForFunction((id) => window.colony.world.locked.has(id), cell, { timeout: 4000 });
      return true;
    } catch (_) {
      return false;
    }
  }

  // Holds the button Scent with the right thumb, or lets it go.
  async function scent(on) {
    if (on === scentOn) return;
    scentOn = on;
    if (kind === "phone") {
      if (on) await touch.down(3, SCENT.x, SCENT.y);
      else await touch.up(3);
    } else if (on) await page.keyboard.down("Shift");
    else await page.keyboard.up("Shift");
  }

  return { push, rest, release, goTo, walk, look, lock, tapLock, scent, waitAlive };
}

module.exports = { launch, open, player, gridOf, reach };
