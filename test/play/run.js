// The play tests of plan 0002, section 5.3.
//
//   node test/play/run.js [alone] [helpers] [two] [demo]
//
// With no names, all the tests run in this order. The script starts and stops the server.
// `mix` must be on the PATH. The screenshots go to docs/playtests/0002/.
//
// All the tests use a phone size (390 x 844) and real touch events. The left thumb stays
// on the stick while the right thumb taps Lock or holds Scent.

const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { launch, open, player, gridOf, reach } = require("./browser");

const ROOT = path.resolve(__dirname, "../..");
const SHOTS = path.join(ROOT, "docs/playtests/0002");
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "colony-play-"));
const SEED = process.env.COLONY_SEED || "2027";
const results = {};
let server = null;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const seconds = (from) => Math.round((Date.now() - from) / 100) / 10;

async function up() {
  for (let i = 0; i < 240; i++) {
    try {
      if ((await fetch("http://localhost:4000/")).ok) return;
    } catch (_) {
      // The server does not listen yet.
    }
    await sleep(250);
  }
  throw new Error("The server did not start.");
}

async function start(workers, helpers, name) {
  const env = {
    ...process.env,
    PORT: "4000",
    COLONY_WORKERS: String(workers),
    COLONY_HELPERS: String(helpers),
    COLONY_SAVE_FILE: path.join(WORK, `${name}.bin`),
    COLONY_SEED: SEED,
  };
  server = spawn("mix", ["phx.server"], { cwd: ROOT, env, stdio: ["ignore", "pipe", "pipe"] });
  server.log = "";
  server.stdout.on("data", (data) => (server.log += data));
  server.stderr.on("data", (data) => (server.log += data));
  await up();
}

// Stops the server in the usual way. The server saves the world first.
async function stop() {
  if (!server) return;
  const done = new Promise((resolve) => server.on("exit", resolve));
  server.kill("SIGTERM");
  await done;
  server = null;
}

function check(condition, text) {
  if (!condition) throw new Error(`Failed: ${text}`);
  console.log(`  ok: ${text}`);
}

async function until(session, text, done, limit) {
  const end = Date.now() + limit;
  while (Date.now() < end) {
    const now = await session.state();
    if (done(now)) return now;
    await sleep(150);
  }
  throw new Error(`Failed: ${text} in ${limit / 1000} s`);
}

// ---------------------------------------------------------------------------
// The way of a new player

// True if a free body can go on foot from the nest to the far bank.
function crossed(grid, now) {
  return [...reach(grid, now.locked, now.nest).steps.keys()].some((cell) => grid.kind(cell) === "far");
}

// The bodies of the bridge that starts at the cell `start` of the near bank, or of the
// bridge that has the body `start`: the locked cells that touch each other.
function bridgeOf(grid, now, start) {
  const seen = new Set();
  const front = grid.neighbors(start).filter((cell) => cell in now.locked);
  if (start in now.locked) front.push(start);
  for (const cell of front) seen.add(cell);
  while (front.length) {
    for (const next of grid.neighbors(front.pop())) {
      if (next in now.locked && !seen.has(next)) {
        seen.add(next);
        front.push(next);
      }
    }
  }
  return [...seen];
}

// A new player builds a bridge from the cell `edge` of the near bank in the direction of
// the point `goal`:
//
//   The player pushes forward and taps Lock when the button is bright. If the button is
//   not bright, the player tries the two sides, then one step back.
//
// The player holds Scent while it walks. Returns the number of locks.
async function build(session, me, edge, goal, options = {}) {
  const first = await session.state();
  const grid = gridOf(first.grid);
  let locks = 0;
  const limit = options.limit || 60;

  for (;;) {
    await me.waitAlive();
    let now = await session.state();
    if (crossed(grid, now) && bridgeOf(grid, now, edge).some((cell) => grid.neighbors(cell).some((next) => grid.kind(next) === "far"))) break;
    check(locks < limit, `the bridge is complete with fewer than ${limit} locks`);

    // Go to the end of the bridge: the body in the highest row. With no body, the bank.
    const bodies = bridgeOf(grid, now, edge);
    const top = bodies.length ? Math.max(...bodies.map(grid.row)) : -1;
    const [gx, gz] = goal;
    const near = (cell) => Math.hypot(grid.center(cell)[0] - gx, grid.center(cell)[1] - gz);
    let stand = bodies.length ? bodies.filter((cell) => grid.row(cell) === top).sort((a, b) => near(a) - near(b))[0] : edge;
    await me.scent(true);
    if (!(await me.walk(stand))) continue;

    // Push forward: to the cell of the next row that is nearest to the goal.
    let done = false;
    const ahead = grid.neighbors(stand).filter((cell) => grid.row(cell) === grid.row(stand) + 1 && grid.kind(cell) === "gap" && !(cell in now.locked));
    ahead.sort((a, b) => near(a) - near(b));
    for (const cell of ahead) {
      if (await me.lock(cell)) {
        done = true;
        break;
      }
    }

    // The button is not bright: try the two sides, then one step back, and so on.
    if (!done && options.onStop && !options.stopped) {
      options.stopped = true;
      await options.onStop(await session.state());
    }
    while (!done && grid.kind(stand) === "gap") {
      for (const cell of grid.beside(stand)) {
        now = await session.state();
        if (grid.kind(cell) !== "gap" || cell in now.locked) continue;
        if (await me.lock(cell)) {
          done = true;
          break;
        }
      }
      if (done) break;
      // One step back: the body of the bridge in the row before, that touches this body.
      now = await session.state();
      const back = grid.neighbors(stand).filter((cell) => grid.row(cell) === grid.row(stand) - 1 && cell in now.locked);
      if (back.length === 0) break;
      stand = back[0];
      await me.walk(stand);
    }
    check(done, `lock ${locks + 1} is possible`);
    locks++;
    if (options.onLock) await options.onLock(locks);
    // The new body cannot lock for 1 second.
    await sleep(300);
  }
  await me.scent(false);
  return locks;
}

// The cell of the edge of the near bank in a column.
const edgeCell = (grid, now, col) => grid.cell(now.grid.nearRows - 1, col);

// ---------------------------------------------------------------------------
// 1. A new player alone: 30 workers and no helper.

async function alone(browser) {
  await start(30, 0, "alone");
  const session = await open(browser, "phone");
  const began = Date.now();
  const me = player(session);
  const first = await session.state();
  const grid = gridOf(first.grid);
  const result = { name: first.name, river: first.grid.river.join(" ") };
  await session.shot(path.join(SHOTS, "01-start.jpg"));
  check(first.workers === 30, "the page shows 30 free workers");

  // The player sees the light of the pile and goes to the river there, with Scent.
  const pile = first.pile;
  const goal = grid.center(pile.cell);
  const edge = edgeCell(grid, first, grid.col(pile.cell));
  await me.scent(true);
  check(await me.walk(edge), "walk to the river with Scent, two thumbs");
  let now = await session.state();
  check(now.scentHeld && now.scent > 5, `the button Scent is held, and ${now.scent} cells have scent`);
  result.width = first.grid.river[grid.col(pile.cell)];

  let shown = false;
  result.bodies = await build(session, me, edge, goal, {
    onLock: async (count) => {
      if (count === 1) {
        result.firstLockSeconds = seconds(began);
        const after = await session.state();
        result.firstBody = after.alive ? "the body of a worker" : "no body";
        check(after.alive, "after the first lock, the player has the body of a worker immediately");
        check(after.workers === 29, "the colony has one free worker fewer: 29");
      }
      if (count === 3 && !shown) {
        shown = true;
        // The marks of the reach show before the next lock.
        const tip = await session.state();
        const top = Math.max(...Object.keys(tip.locked).map(Number).map(grid.row));
        const body = Object.keys(tip.locked).map(Number).find((cell) => grid.row(cell) === top);
        await me.walk(body);
        await me.look(grid.straight(body));
        const reachNow = (await session.state()).reach;
        result.reachAtThree = reachNow;
        await session.shot(path.join(SHOTS, "02-reach.jpg"));
      }
    },
  });
  result.bridgeSeconds = seconds(began);
  check(result.bodies <= result.width + 2, `the first bridge has ${result.bodies} bodies across ${result.width} rows`);

  // Cross with Scent to the pile. The workers follow the scent and carry the food.
  await me.scent(true);
  now = await session.state();
  const beside = grid.neighbors(pile.cell).find((cell) => reach(grid, now.locked, now.cell).steps.has(cell));
  await me.walk(beside);
  await me.scent(false);
  await me.rest();
  now = await until(session, "the message of the pile", (state) => /food/.test(state.banner), 10000);
  result.atPileSeconds = seconds(began);
  await session.shot(path.join(SHOTS, "03-at-the-pile.jpg"));

  now = await until(session, "the first food at the nest", (state) => state.foodNest > 0, 120000);
  result.firstFoodSeconds = seconds(began);
  check(result.firstFoodSeconds < 90, `the first food is at the nest in less than 90 seconds from the load: ${result.firstFoodSeconds} s`);

  // The record of the bridge shows for 5 seconds, with the name of the player.
  now = await until(session, "the record on the page", (state) => state.card !== "", 5000);
  check(now.card.includes(first.name), `the record shows the name of the player: "${now.card}"`);
  await session.shot(path.join(SHOTS, "04-record.jpg"));
  check(now.records.length === 1 && now.records[0].names[0].name === first.name, "the list of records has the record");
  result.record = now.records[0];

  // A place 12 rows wide: the player goes there along the bank with Scent and builds.
  // The columns near it are 12 rows wide or more. Thus a bridge there cannot end on the
  // bank of a narrower column: it has bodies in 12 rows.
  const river = first.grid.river;
  const wide = (col) => [-3, -2, -1, 1, 2, 3].every((step) => (river[col + step] || 99) >= 12);
  const column = river
    .map((width, col) => ({ width, col }))
    .filter((place) => place.width === 12 && place.col > 2 && place.col < grid.width - 3 && wide(place.col))
    .sort((a, b) => Math.abs(a.col - grid.col(pile.cell)) - Math.abs(b.col - grid.col(pile.cell)))[0].col;
  const before = Object.keys((await session.state()).locked).length;
  const wideEdge = edgeCell(grid, first, column);
  await me.scent(true);
  check(await me.walk(wideEdge), `walk to a place 12 rows wide, in column ${column}`);
  const wideGoal = grid.center(grid.cell(first.grid.nearRows + 12, column));
  const wideBegan = Date.now();
  let limitShot = false;
  result.wideBodies = await build(session, me, wideEdge, wideGoal, {
    onStop: async () => {
      if (limitShot) return;
      limitShot = true;
      // One body wide stops at row 7. The player looks at a side: the marks show the new reach.
      await session.shot(path.join(SHOTS, "05-one-wide-stops.jpg"));
    },
    onLock: async (count) => {
      if (count === 12) await session.shot(path.join(SHOTS, "06-wide-bridge.jpg"));
    },
  });
  result.wideSeconds = seconds(wideBegan);
  now = await session.state();
  check(Object.keys(now.locked).length === before + result.wideBodies, "each lock of the player made one body");
  check(result.wideBodies <= 24, `the player crosses 12 rows with 24 bodies or fewer: ${result.wideBodies}`);
  // The rows of the river that have a body of this bridge, and the bodies in each row.
  const wideRows = {};
  for (const cell of bridgeOf(grid, now, wideEdge)) {
    const row = grid.row(cell) - first.grid.nearRows + 1;
    wideRows[row] = (wideRows[row] || 0) + 1;
  }
  result.wideRows = Object.keys(wideRows).length;
  check(result.wideRows >= 12, `the bridge has bodies in 12 rows: ${result.wideRows}`);
  result.wideLines = Object.values(wideRows).join(" ");
  await me.walk(grid.cell(first.grid.nearRows + 12, column));
  await me.rest();
  await session.shot(path.join(SHOTS, "07-across-12-rows.jpg"));

  // A tap on a body shows the name, the time and the count.
  // The player stands some rows back and taps a body that is higher on the screen:
  // the controls do not cover it.
  now = await session.state();
  const rows = bridgeOf(grid, now, wideEdge).sort((a, b) => grid.row(b) - grid.row(a));
  await me.walk(rows.find((cell) => grid.row(cell) === grid.row(rows[0]) - 5));
  await me.release();
  const tapped = rows.find((cell) => grid.row(cell) === grid.row(rows[0]) - 1);
  const at = await session.page.evaluate((cell) => {
    const body = window.colony.world.locked.get(cell);
    return window.colony.renderer.project(body.x, 0.1, body.z);
  }, tapped);
  await session.touch.tap(4, at[0], at[1]);
  await sleep(700);
  result.tapText = await session.page.evaluate(() => (document.getElementById("info").hidden ? "" : document.getElementById("info").textContent));
  check(result.tapText.startsWith(first.name) && /went across/.test(result.tapText), `a tap shows the name, the time and the count: "${result.tapText}"`);
  await session.shot(path.join(SHOTS, "08-tap.jpg"));

  // The page and the server calculate the same support.
  const same = await session.page.evaluate(() => {
    const { world, support } = window.colony;
    const has = (cell) => world.locked.has(cell);
    const mine = support.calculate(world.grid, world.rule, [...world.locked.keys()], has);
    return [...world.locked].every(([cell, body]) => mine.get(cell) === body.support);
  });
  check(same, "the page calculates the same support as the server for each body");

  result.corrections = now.corrections;
  if (now.corrections > 0) console.log(`  refused moves: ${JSON.stringify(now.refused)}`);
  check(now.corrections === 0, `the server refused no move of the player: ${now.corrections}`);
  check(session.errors.length === 0, "the page has no errors");
  await session.context.close();
  await stop();
  results.alone = result;
}

// ---------------------------------------------------------------------------
// 2. One player and 3 helpers. 3. Two browsers and 2 helpers.

// The player goes to the bridge of the helpers and locks bodies there, while the helpers
// build. Returns the number of locks of the player.
async function join(session, me, wanted) {
  const first = await session.state();
  const grid = gridOf(first.grid);
  let locks = 0;
  const end = Date.now() + 90000;
  while (locks < wanted && Date.now() < end) {
    await me.waitAlive();
    const now = await session.state();
    if (crossed(grid, now)) break;
    const bodies = Object.keys(now.locked).map(Number);
    if (bodies.length === 0) {
      await sleep(300);
      continue;
    }
    // Go to the end of the bridge, with Scent, and lock in the next row or beside.
    const top = Math.max(...bodies.map(grid.row));
    const stand = bodies.find((cell) => grid.row(cell) === top);
    await me.scent(true);
    if (!(await me.walk(stand))) continue;
    const cells = [...grid.neighbors(stand).filter((cell) => grid.row(cell) === top + 1), ...grid.beside(stand)];
    for (const cell of cells) {
      const fresh = await session.state();
      if (grid.kind(cell) !== "gap" || cell in fresh.locked) continue;
      if (await me.lock(cell)) {
        locks++;
        break;
      }
    }
    await sleep(300);
  }
  await me.scent(false);
  await me.rest();
  return locks;
}

async function helpers(browser) {
  await start(30, 3, "helpers");
  const session = await open(browser, "phone");
  const me = player(session);
  const first = await session.state();
  const result = { name: first.name };
  check(first.players.filter((other) => other.helper).length === 3, "the page shows 3 helpers");
  const labels = await session.page.evaluate(() => [...document.querySelectorAll("#labels div.helper")].map((div) => div.textContent));
  check(labels.length > 0 && labels.every((text) => /^Helper \d$/.test(text)), `the names of the helpers have their own look: ${labels.join(", ")}`);

  result.locks = await join(session, me, 3);
  check(result.locks >= 1, `the player locked ${result.locks} bodies in the bridge of the helpers`);
  await session.shot(path.join(SHOTS, "09-with-helpers.jpg"));

  const now = await until(session, "a record", (state) => state.records.length > 0, 120000);
  const record = now.records[0];
  const names = record.names.map((entry) => `${entry.name} ${entry.bodies}${entry.helper ? " (helper)" : ""}`);
  check(record.names.some((entry) => entry.name === first.name && !entry.helper), `the record has the name of the player: ${names.join(", ")}`);
  check(record.names.some((entry) => entry.helper && /^Helper/.test(entry.name)), "the record has the names of helpers");
  const card = await until(session, "the record on the page", (state) => state.card !== "", 5000);
  check(card.card.includes(first.name), "the player sees the record at the first food");
  await session.shot(path.join(SHOTS, "10-record-with-helpers.jpg"));
  result.record = record;
  check(session.errors.length === 0, "the page has no errors");
  await session.context.close();
  await stop();
  results.helpers = result;
}

async function two(browser) {
  await start(30, 2, "two");
  const one = await open(browser, "phone");
  const other = await open(browser, "phone");
  const a = player(one);
  const b = player(other);
  const names = [(await one.state()).name, (await other.state()).name];
  check(names[0] !== names[1], `the two browsers have different names: ${names.join(", ")}`);

  // The two players lock bodies in the bridge at the same time.
  const [locksA, locksB] = await Promise.all([join(one, a, 2), join(other, b, 2)]);
  check(locksA >= 1 && locksB >= 1, `each player locked bodies: ${locksA} and ${locksB}`);

  const first = await until(one, "a record", (state) => state.records.length > 0, 120000);
  await sleep(1500);
  const second = await other.state();
  const record = first.records[0];
  const inRecord = (name) => record.names.some((entry) => entry.name === name && !entry.helper);
  check(inRecord(names[0]) && inRecord(names[1]), `one record has the two names: ${record.names.map((entry) => `${entry.name} ${entry.bodies}`).join(", ")}`);
  // The food of a record grows with the time. All the other values must be the same.
  const fixed = (record) => JSON.stringify([record.id, record.time, record.seconds, record.rows, record.bodies, record.width, record.names]);
  const same = (x, y) => fixed(x) === fixed(y);
  check(second.records.length > 0 && same(record, second.records[0]), "each browser shows the same record");

  // Each browser opens the list of the records.
  for (const [session, file] of [[one, "11-two-browsers-a.jpg"], [other, "12-two-browsers-b.jpg"]]) {
    const button = await session.page.evaluate(() => {
      const box = document.getElementById("open").getBoundingClientRect();
      return [box.left + box.width / 2, box.top + box.height / 2];
    });
    await session.touch.tap(5, button[0], button[1]);
    await sleep(400);
    const text = await session.page.evaluate(() => (document.getElementById("records").hidden ? "" : document.getElementById("list").textContent));
    check(text.includes(names[0]) && text.includes(names[1]), `the list of ${session === one ? names[0] : names[1]} has the two names`);
    await session.shot(path.join(SHOTS, file));
  }
  results.two = { names, record };
  check(one.errors.length === 0 && other.errors.length === 0, "the pages have no errors");
  await one.context.close();
  await other.context.close();
  await stop();
}

// ---------------------------------------------------------------------------
// 4. Demo mode: 4 helpers and no player.

async function demo(browser) {
  await start(30, 0, "demo");
  const session = await open(browser, "phone", "&demo=1");
  const began = Date.now();
  const first = await session.state();
  const grid = gridOf(first.grid);
  const result = {};
  check(!first.alive, "the demo has no player");

  const times = { firstLock: null, complete: null, firstFood: null };
  const shots = [5, 15, 30];
  while (seconds(began) < 75 && (times.firstFood === null || shots.length > 0)) {
    const now = await session.state();
    const count = Object.keys(now.locked).length;
    if (times.firstLock === null && count > 0) times.firstLock = seconds(began);
    if (times.complete === null && crossed(grid, now)) {
      times.complete = seconds(began);
      result.bodies = count;
    }
    if (times.firstFood === null && now.foodNest > 0) times.firstFood = seconds(began);
    if (shots.length > 0 && seconds(began) >= shots[0]) {
      const at = shots.shift();
      await session.shot(path.join(SHOTS, `13-demo-${String(at).padStart(2, "0")}-seconds.jpg`));
      result[`at${at}`] = { locked: count, helpers: now.players.filter((other) => other.helper).length, food: now.foodNest };
    }
    await sleep(100);
  }
  Object.assign(result, times);
  check(result.at5.helpers === 4, "the demo has 4 helpers");
  check(times.complete !== null, `the first bridge is complete: ${times.complete} s after the load`);
  result.growSeconds = Math.round((times.complete - 0) * 10) / 10;
  check(times.complete >= 15 && times.complete <= 45, `the first bridge grows for 15 to 45 seconds: ${times.complete} s`);
  check(times.firstFood !== null && times.firstFood > times.complete, `then food goes across: first food at ${times.firstFood} s`);
  check(session.errors.length === 0, "the page has no errors");
  await session.context.close();
  await stop();
  results.demo = result;
}

(async () => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const names = process.argv.slice(2);
  const run = (name) => names.length === 0 || names.includes(name);
  const browser = await launch();
  try {
    if (run("alone")) {
      console.log("1. A new player alone, 30 workers");
      await alone(browser);
    }
    if (run("helpers")) {
      console.log("2. One player and 3 helpers");
      await helpers(browser);
    }
    if (run("two")) {
      console.log("3. Two browsers and 2 helpers");
      await two(browser);
    }
    if (run("demo")) {
      console.log("4. Demo mode");
      await demo(browser);
    }
    console.log(JSON.stringify(results, null, 2));
  } catch (error) {
    console.log(error.stack || String(error));
    console.log(JSON.stringify(results, null, 2));
    process.exitCode = 1;
  } finally {
    await browser.close();
    await stop();
    fs.rmSync(WORK, { recursive: true, force: true });
  }
})();
