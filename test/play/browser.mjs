// A browser for the play tests: Chromium at phone size, with real touch events.

import { createRequire } from "node:module";
import { NewPlayer } from "./newplayer.mjs";

// Playwright can be in the folder of the project or in a global folder.
const { chromium } = createRequire(import.meta.url)("playwright");

export const BASE = process.env.COLONY_URL || "http://localhost:4000/";
// The test machine has no graphics card: the browser draws with software.
const ARGS = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required"];

// The places of the controls on a screen of 390 x 844.
export const STICK = { x: 90, y: 740, radius: 46 };
export const LOCK = { x: 320, y: 754 };

export function launch() {
  return chromium.launch({ args: ARGS });
}

// Opens the game at phone size. `query` is added to the address, for example "&story=1".
// `before` is a function that runs in the page before the code of the page.
export async function open(browser, query = "", wait = true, before = null) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, hasTouch: true, isMobile: true, acceptDownloads: true });
  const page = await context.newPage();
  if (before) await page.addInitScript(before);
  const errors = [];
  page.on("console", (message) => message.type() === "error" && errors.push(message.text()));
  page.on("pageerror", (error) => errors.push(error.message));
  // The software renderer is slow: the tests use fewer pixels. The screenshots use all.
  await page.goto(`${BASE}?scale=0.5${query}`);
  if (wait) await page.waitForFunction(() => window.colony && window.colony.world.ready);
  const cdp = await context.newCDPSession(page);

  // Real touch events. Each finger has a number: 1 is the left thumb, 2 is the right thumb.
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
      const finger = fingers.get(id);
      if (!finger) return;
      fingers.delete(id);
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [{ id, x: finger.x, y: finger.y }] });
    },
    async tap(id, x, y) {
      await touch.down(id, x, y);
      await page.waitForTimeout(60);
      await touch.up(id);
    },
  };

  // The left thumb pushes the stick: [right, up] from -1 to 1.
  let held = false;
  const stick = async (x, y) => {
    if (x === 0 && y === 0) {
      if (held) await touch.up(1);
      held = false;
      return;
    }
    if (!held) {
      await touch.down(1, STICK.x, STICK.y);
      held = true;
    }
    await touch.move(1, STICK.x + x * STICK.radius, STICK.y - y * STICK.radius);
  };
  const tapLock = () => touch.tap(2, LOCK.x, LOCK.y);
  // A tap on the middle of an element of the page.
  const tapOn = async (id) => {
    const at = await page.evaluate((name) => {
      const box = document.getElementById(name).getBoundingClientRect();
      return [box.left + box.width / 2, box.top + box.height / 2];
    }, id);
    await touch.tap(3, at[0], at[1]);
  };

  // The numbers of the game that a test reads.
  const state = () =>
    page.evaluate(() => {
      const { world, player } = window.colony;
      return {
        x: world.me.x, z: world.me.z, carry: world.me.carry, name: world.me.name,
        spare: world.freeWorkers, food: world.foodNest, stage: world.stage, complete: world.complete,
        locks: player.locks, noLocks: player.noLocks, locked: world.locked.size, corrections: player.corrections,
        // The land that the body is on, or -1 on a bridge.
        land: ((cell) => (cell >= 0 && world.grid.kind(cell) === 0 ? world.grid.land(cell) : -1))(world.grid.cellAt(world.me.x, world.me.z)),
        moment: window.colony.moment(),
        sound: { ...window.colony.sound.counts, running: Boolean(window.colony.sound.context && window.colony.sound.context.state === "running") },
        story: window.colony.story.state(),
        records: window.colony.records(), view: window.colony.view(), times: window.colony.times(),
        piles: [...world.piles.values()].map((pile) => ({ id: pile.id, units: pile.units, far: pile.far, cell: pile.cell })),
        cell: world.grid.cellAt(world.me.x, world.me.z),
      };
    });

  // A screenshot with all the pixels. The time of the page stops for it: the picture is
  // the picture of one moment.
  const shot = async (path) => {
    await page.evaluate(() => {
      window.colony.freeze(true);
      window.colony.renderer.scale = 2;
    });
    await page.waitForTimeout(500);
    await page.screenshot({ path, type: "jpeg", quality: 82 });
    await page.evaluate(() => {
      window.colony.renderer.scale = 0.5;
      window.colony.freeze(false);
    });
  };

  return { context, page, touch, stick, tapLock, tapOn, state, shot, errors };
}

// Plays with the script of the new player until `done(state, seconds)` is true or the
// time is at its end. `each(state, seconds)` gets each state.
export async function playNew(session, { limit, done, each }) {
  const script = new NewPlayer();
  const start = Date.now();
  let last = null;
  for (;;) {
    const now = Date.now();
    const state = await session.state();
    const seconds = (now - start) / 1000;
    if (each) await each(state, seconds);
    if (done(state, seconds) || seconds > limit) {
      await session.stick(0, 0);
      return state;
    }
    const moved = last === null || Math.hypot(state.x - last.x, state.z - last.z) > 0.03;
    last = state;
    const action = script.step(state.view, moved, now);
    await session.stick(action.stick[0], action.stick[1]);
    if (action.tap) await session.tapLock();
    const wait = 100 - (Date.now() - now);
    if (wait > 0) await session.page.waitForTimeout(wait);
  }
}
