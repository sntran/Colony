// The play tests of plan 0001, section 5.3.
//
//   node test/play/run.js [alone] [scent] [two] [reload] [restart]
//
// With no names, all the tests run in this order. The tests "two", "reload" and "restart"
// use the world of the test "scent". The script starts and stops the server. `mix` must be
// on the PATH. The screenshots go to docs/playtests/0001/.

const { spawn } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { launch, open, player, gridOf, reach } = require("./browser");

const ROOT = path.resolve(__dirname, "../..");
const SHOTS = path.join(ROOT, "docs/playtests/0001");
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "colony-play-"));
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

async function start(workers, save) {
  const env = { ...process.env, PORT: "4000", COLONY_WORKERS: String(workers), COLONY_SAVE_FILE: save, COLONY_SEED: "2026" };
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
  const log = server.log;
  server = null;
  return log;
}

function check(condition, text) {
  if (!condition) throw new Error(`Failed: ${text}`);
  console.log(`  ok: ${text}`);
}

// ---------------------------------------------------------------------------
// 1. With 0 workers, cross the gap alone and touch the food. Phone size, touch events.

async function alone(browser) {
  await start(0, path.join(WORK, "alone.bin"));
  const session = await open(browser, "phone");
  const began = Date.now();
  const me = player(session);
  const first = await session.state();
  const grid = gridOf(first.grid);
  const result = { name: first.name };
  await session.shot(path.join(SHOTS, "01-start.jpg"));

  // The player goes straight to the gap, as a new player does.
  const column = first.nest % grid.width;
  const edge = grid.cell(first.grid.nearRows - 1, column);
  await me.walk(edge);
  let now = await session.state();
  check(now.lockReady, "the button Lock is bright at the gap");
  await session.shot(path.join(SHOTS, "02-at-the-gap.jpg"));

  // The way of a new player: go to the end of the bridge and lock in the next row. If that
  // is not possible, lock beside the body that is nearest to the end and alone in its row.
  let locks = 0;
  let shownLimit = false;
  for (;;) {
    await me.waitAlive();
    now = await session.state();
    const walkable = reach(grid, now.locked, now.cell);
    if ([...walkable.steps.keys()].some((cell) => grid.kind(cell) === "far")) break;

    const frontier = new Set(now.frontier);
    const bodies = Object.keys(now.locked).map(Number);
    const top = bodies.length ? Math.max(...bodies.map(grid.row)) : first.grid.nearRows - 1;
    const options = [];
    const besideOf = (cell) => grid.neighbors(cell).filter((next) => grid.row(next) === grid.row(cell) && next in now.locked);
    for (const stand of bodies.length ? bodies : [edge]) {
      for (const target of grid.neighbors(stand)) {
        if (!frontier.has(target)) continue;
        const row = grid.row(target);
        // A cell beside a body is useful only if that body is alone in its row.
        const beside = besideOf(target);
        const useful = row > top || (beside.length === 1 && besideOf(beside[0]).length === 0);
        if (useful) options.push({ stand, target, row });
      }
    }
    // A cell in a new row is best. If there is none, the highest row is best. Between two
    // cells of the same row, the cell nearer to the food is best.
    const foodX = grid.center(now.food)[0];
    const off = (option) => Math.abs(grid.center(option.target)[0] - foodX);
    options.sort((a, b) => b.row - a.row || off(a) - off(b));
    const option = options[0];
    check(option !== undefined, `lock ${locks + 1} is possible`);

    if (!shownLimit && bodies.length > 0 && option.row <= top) {
      // The bridge cannot grow in a straight line. Show what the player sees at its end.
      const last = bodies.find((cell) => grid.row(cell) === top);
      await me.walk(last);
      await session.shot(path.join(SHOTS, "03-one-cell-wide-stops.jpg"));
      result.rowsOneWide = top - first.grid.nearRows + 1;
      shownLimit = true;
    }

    if (!(await me.walk(option.stand))) {
      const at = await session.state();
      console.log(`  the walk to cell ${option.stand} stopped at cell ${at.cell} (${at.x.toFixed(2)}, ${at.z.toFixed(2)}), alive: ${at.alive}`);
    }
    check((await session.state()).cell === option.stand, `walk to the cell for lock ${locks + 1}`);
    check(await me.lock(option.target), `lock ${locks + 1} in row ${option.row - first.grid.nearRows + 1} of the gap`);
    locks++;
    if (locks === 1) result.firstLockSeconds = seconds(began);
  }
  result.bodies = locks;
  result.bridgeSeconds = seconds(began);
  await session.shot(path.join(SHOTS, "04-bridge-complete.jpg"));

  // Cross the bridge and touch the food.
  now = await session.state();
  const beside = grid.neighbors(now.food).find((cell) => grid.row(cell) < grid.row(now.food));
  await me.walk(beside);
  const [fx, fz] = grid.center(now.food);
  await me.goTo(fx, fz, 0.9);
  await session.page.waitForFunction(() => !document.getElementById("banner").hidden, null, { timeout: 5000 });
  now = await session.state();
  result.foodSeconds = seconds(began);
  result.banner = now.banner;
  await session.shot(path.join(SHOTS, "05-at-the-food.jpg"));
  check(/food/.test(now.banner), `the page tells that the player is at the food: "${now.banner}"`);
  check(result.foodSeconds < 240, `the time is less than 4 minutes: ${result.foodSeconds} s`);
  check(session.errors.length === 0, "the page has no errors");
  await session.context.close();
  await stop();
  results.alone = result;
}

// ---------------------------------------------------------------------------
// 2. With 200 workers, put scent from the nest to the gap. Do not lock.
//    Desktop size, key events.

const shared = path.join(WORK, "shared.bin");

async function scent(browser) {
  await start(200, shared);
  const session = await open(browser, "desk", "&stats=1");
  const began = Date.now();
  const me = player(session);
  const first = await session.state();
  const grid = gridOf(first.grid);
  const result = {};

  await me.scent(true);
  await me.walk(grid.cell(first.grid.nearRows - 1, first.nest % grid.width));
  await me.scent(false);
  result.scentSeconds = seconds(began);
  await session.shot(path.join(SHOTS, "06-scent.jpg"));

  const until = async (text, done, limit) => {
    const end = Date.now() + limit;
    while (Date.now() < end) {
      const now = await session.state();
      if (done(now)) return now;
      await sleep(100);
    }
    throw new Error(`Failed: ${text} in ${limit / 1000} s`);
  };
  await until("a worker locks", (now) => Object.keys(now.locked).length > 0, 60000);
  result.firstWorkerLockSeconds = seconds(began);
  await until("the bridge is complete", (now) => {
    const far = [...reach(grid, now.locked, now.nest).steps.keys()].some((cell) => grid.kind(cell) === "far");
    return far;
  }, 120000);
  result.bridgeSeconds = seconds(began);
  await session.shot(path.join(SHOTS, "07-workers-bridge.jpg"));
  let now = await until("food at the nest", (state) => state.foodNest > 0, 300000);
  result.firstFoodSeconds = seconds(began);
  result.bodiesInBridge = Object.keys(now.locked).length;
  check(Object.values(now.locked).every((body) => body.kind === 0), "the player did not lock: all locked bodies are workers");

  // Go back to the nest and look at the workers that carry food.
  await me.walk(first.nest);
  await sleep(2500);
  await session.shot(path.join(SHOTS, "08-food-at-the-nest.jpg"));
  now = await session.state();
  result.foodAfterWalkBack = now.foodNest;
  result.stats = await session.page.evaluate(() => document.getElementById("stats").textContent.replace(/\s+/g, " "));
  check(session.errors.length === 0, "the page has no errors");
  await session.context.close();
  results.scent = result;
}

// ---------------------------------------------------------------------------
// 3. Two browsers in one world show the same bridge and the same names.

const sameWorld = (a, b) => JSON.stringify(Object.entries(a.locked).sort()) === JSON.stringify(Object.entries(b.locked).sort());

async function two(browser) {
  const desk = await open(browser, "desk");
  const phone = await open(browser, "phone");
  const a = player(desk);
  const b = player(phone);
  const first = await desk.state();
  const grid = gridOf(first.grid);
  const column = first.nest % grid.width;
  const row = first.grid.nearRows;
  const result = { desk: first.name, phone: (await phone.state()).name };
  check(result.desk !== result.phone, `the two browsers have different names: ${result.desk}, ${result.phone}`);

  // Each player locks two bodies from the bank. The cells are more than 6 cells from the
  // scent: the workers do not go there, thus they do not lock in these cells first.
  for (const [who, session, col] of [[a, desk, column - 9], [b, phone, column + 9]]) {
    for (const cell of [grid.cell(row, col), grid.cell(row + 1, col)]) {
      await who.waitAlive();
      const now = await session.state();
      const stand = grid.neighbors(cell).find((next) => grid.row(next) === grid.row(cell) - 1 && (grid.kind(next) === "near" || next in now.locked));
      check(await who.walk(stand), `${session.kind}: walk to the gap`);
      if (!(await who.lock(cell))) {
        const at = await session.state();
        console.log(`  lock of cell ${cell} failed: body at cell ${at.cell}, selected cell ${at.target}, alive ${at.alive}`);
      }
      check(cell in (await session.state()).locked, `${session.kind}: lock`);
    }
  }
  await a.waitAlive();
  await b.waitAlive();
  // The two players meet at the bridge of the workers.
  await a.walk(grid.cell(row - 2, column - 1));
  await b.walk(grid.cell(row - 2, column + 1));
  await sleep(1500);

  const sa = await desk.state();
  const sb = await phone.state();
  const mine = (state, name) => Object.values(state.locked).filter((body) => body.kind === 1 && body.name === name).length;
  check(sameWorld(sa, sb), `the two browsers have the same ${Object.keys(sa.locked).length} locked bodies, with the same names, times and support`);
  check(mine(sa, result.desk) === 2 && mine(sb, result.desk) === 2, `the two browsers show 2 bodies of ${result.desk}`);
  check(mine(sa, result.phone) === 2 && mine(sb, result.phone) === 2, `the two browsers show 2 bodies of ${result.phone}`);
  check(sa.players === 2 && sb.players === 2, "each browser shows 2 players");
  const label = (session) => session.page.evaluate(() => [...document.querySelectorAll("#labels div")].map((div) => div.textContent));
  check((await label(desk)).includes(result.phone), "the desktop shows the name of the phone player above its body");
  check((await label(phone)).includes(result.desk), "the phone shows the name of the desktop player above its body");
  result.locked = Object.keys(sa.locked).length;
  await desk.shot(path.join(SHOTS, "09-two-browsers-desktop.jpg"));

  // On the phone, go to the bodies of the desktop player and tap one.
  await b.walk(grid.cell(row - 1, column - 8));
  const at = await phone.page.evaluate((cell) => {
    const body = window.colony.world.locked.get(cell);
    return window.colony.renderer.project(body.x, 0.1, body.z);
  }, grid.cell(row, column - 9));
  await phone.touch.tap(4, at[0], at[1]);
  await sleep(400);
  result.tapText = await phone.page.evaluate(() => (document.getElementById("info").hidden ? "" : document.getElementById("info").textContent));
  check(result.tapText.startsWith(result.desk), `a tap on a body shows its name and time: "${result.tapText}"`);
  await phone.shot(path.join(SHOTS, "10-two-browsers-phone.jpg"));

  results.two = result;
  return { desk, phone };
}

// ---------------------------------------------------------------------------
// 4. Load the page again. The world is the same.

const playerBodies = (state) => JSON.stringify(Object.entries(state.locked).filter(([, body]) => body.kind === 1).sort());

async function reload(sessions) {
  const { desk } = sessions;
  const before = await desk.state();
  await desk.page.reload();
  await desk.page.waitForFunction(() => window.colony && window.colony.world.ready);
  await sleep(1000);
  const after = await desk.state();
  check(after.name === before.name, `the name is the same after the load: ${after.name}`);
  check(playerBodies(after) === playerBodies(before), "the locked bodies of the players are the same, with names and times");
  check(Object.keys(after.locked).length > 4, `the bridge of the workers is there: ${Object.keys(after.locked).length} locked bodies`);
  check(after.foodNest >= before.foodNest, `the food at the nest is ${after.foodNest} (before: ${before.foodNest})`);
  check(after.scent > 0, `the scent is there: ${after.scent} cells`);
  results.reload = { locked: Object.keys(after.locked).length, foodNest: after.foodNest, scentCells: after.scent };
}

// ---------------------------------------------------------------------------
// 5. Start the server again. The locked bodies of players are there with their names.

async function restart(browser, sessions) {
  const before = await sessions.desk.state();
  await sessions.desk.context.close();
  await sessions.phone.context.close();
  const log = await stop();
  check(/World saved/.test(log), "the server saves the world when it stops");
  await start(200, shared);
  for (let i = 0; i < 40 && !/World loaded|New world/.test(server.log); i++) await sleep(100);
  check(/World loaded/.test(server.log), "the server loads the world at the start");

  const session = await open(browser, "phone");
  await sleep(800);
  const after = await session.state();
  check(playerBodies(after) === playerBodies(before), "the 4 locked bodies of the players are there, with the same names and times");
  check(after.foodNest === before.foodNest || after.foodNest > before.foodNest, `the food at the nest is there: ${after.foodNest}`);
  check(after.name !== before.name, "a new browser has a new name");

  const grid = gridOf(after.grid);
  const me = player(session);
  const [cell, body] = Object.entries(after.locked).find(([, value]) => value.kind === 1);
  const stand = grid.neighbors(Number(cell)).find((next) => grid.kind(next) === "near");
  await me.walk(stand ?? after.nest);
  const at = await session.page.evaluate((id) => {
    const locked = window.colony.world.locked.get(id);
    return window.colony.renderer.project(locked.x, 0.1, locked.z);
  }, Number(cell));
  await session.touch.tap(4, at[0], at[1]);
  await sleep(400);
  const text = await session.page.evaluate(() => (document.getElementById("info").hidden ? "" : document.getElementById("info").textContent));
  check(text.startsWith(body.name), `a tap shows the name after the restart: "${text}"`);
  await session.shot(path.join(SHOTS, "11-after-restart.jpg"));
  results.restart = { playerBodies: Object.values(after.locked).filter((value) => value.kind === 1).length, locked: Object.keys(after.locked).length };
  await session.context.close();
}

(async () => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const names = process.argv.slice(2);
  const run = (name) => names.length === 0 || names.includes(name);
  const browser = await launch();
  try {
    if (run("alone")) {
      console.log("1. Alone, 0 workers, phone size, touch");
      await alone(browser);
    }
    if (run("scent") || run("two") || run("reload") || run("restart")) {
      console.log("2. Scent, 200 workers, desktop size, keys");
      await scent(browser);
      let sessions = null;
      if (run("two") || run("reload") || run("restart")) {
        console.log("3. Two browsers in one world");
        sessions = await two(browser);
      }
      if (run("reload") || run("restart")) {
        console.log("4. Load the page again");
        await reload(sessions);
      }
      if (run("restart")) {
        console.log("5. Start the server again");
        await restart(browser, sessions);
      }
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
