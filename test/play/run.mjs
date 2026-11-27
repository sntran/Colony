// The play tests of plan 0004, section 5.3, in a browser.
//
//     node test/play/run.mjs [slow] [deadscreen] [bodies] [two] [longworld] [shots]
//
// With no name, all the tests run. Each test starts the server with a new world and stops
// it. Stop your server first: the tests use port 4000. Test 2 (fast players with no
// browser) is test/play/fast.mjs.
//
// The tests play in Chromium at 390 x 844 with real touch events. The script of the new
// player is in newplayer.mjs: it knows only what a person sees.

import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { copyFileSync } from "node:fs";
import { startServer } from "./server.mjs";
import { launch, open, playNew } from "./browser.mjs";
import { run as crowd } from "./crowd.mjs";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const SHOTS = path.join(root, "docs/playtests/0004");
mkdirSync(SHOTS, { recursive: true });
const SEEDS = (process.env.SEEDS || "2027,11,42").split(",").map(Number);

const results = [];
function check(test, text, ok, value = "") {
  results.push({ test, text, ok });
  console.log(`${ok ? "met     " : "NOT MET "} ${text}${value === "" ? "" : `: ${value}`}`);
}
const sleep = (time) => new Promise((resolve) => setTimeout(resolve, time));

// The frame time of a page: the median and the 90th percentile of 120 frames, in
// milliseconds, and the parts of the world that the page drew. The page draws with all
// its pixels for the measure.
async function frameTime(session) {
  return session.page.evaluate(async () => {
    const renderer = window.colony.renderer;
    const scale = renderer.scale;
    renderer.scale = 1;
    const times = [];
    let last = performance.now();
    for (let i = 0; i < 121; i++) {
      await new Promise((resolve) => requestAnimationFrame(resolve));
      const now = performance.now();
      if (i > 0) times.push(now - last);
      last = now;
    }
    renderer.scale = scale;
    times.sort((a, b) => a - b);
    return { median: Number(times[60].toFixed(1)), p90: Number(times[108].toFixed(1)), parts: renderer.partsDrawn, all: renderer.parts.length };
  });
}

// The sizes of the messages that a page gets in its first seconds, in bytes.
function countMessages(session) {
  const sizes = [];
  const start = Date.now();
  return session.context.newCDPSession(session.page).then(async (cdp) => {
    await cdp.send("Network.enable");
    cdp.on("Network.webSocketFrameReceived", (event) => {
      if (Date.now() - start > 10000) return;
      const data = event.response.payloadData;
      sizes.push(event.response.opcode === 2 ? Math.floor((data.length * 3) / 4) : data.length);
    });
    return sizes;
  });
}

const tests = {
  // 1. One slow player, 15 minutes.
  async slow() {
    const minutes = Number(process.env.SLOW_MINUTES || 15);
    for (const seed of SEEDS) {
      const server = await startServer({ helpers: 0, seed });
      const browser = await launch();
      try {
        const session = await open(browser);
        const crossings = [];
        let stage = 1;
        const final = await playNew(session, {
          slow: true,
          seed,
          limit: minutes * 60,
          done: () => false,
          each: async (state, seconds) => {
            for (; stage < state.stage; stage++) crossings.push({ river: stage, seconds: Math.round(seconds), spare: state.spare });
          },
        });
        const firstFood = final.times.firstFood === null ? null : (final.times.firstFood - final.times.load) / 1000;
        const river5 = crossings.find((crossing) => crossing.river === 5);
        const spare = crossings.filter((crossing) => crossing.river >= 2 && crossing.river <= 5);
        console.log(`  seed ${seed}: ${final.locks} locks, ${final.stage - 1} crossings, ${final.food} food, crossings ${JSON.stringify(crossings)}, the longest time with no guide and no bright button ${session.longestIdle.toFixed(1)} s`);
        check("slow", `seed ${seed}: the first food is at the nest in less than 60 seconds`, firstFood !== null && firstFood < 60, firstFood === null ? "no food" : `${firstFood.toFixed(0)} s`);
        check("slow", `seed ${seed}: the player crosses river 5 in less than 12 minutes`, Boolean(river5) && river5.seconds < 720, river5 ? `${river5.seconds} s` : `${final.stage - 1} crossings`);
        check("slow", `seed ${seed}: never more than 20 seconds with no guide and no bright button`, session.longestIdle <= 20, `${session.longestIdle.toFixed(1)} s`);
        check("slow", `seed ${seed}: 60 spare bodies or fewer at the crossings of rivers 2 to 5`, spare.length === 4 && spare.every((crossing) => crossing.spare <= 60), spare.map((crossing) => `${crossing.river}: ${crossing.spare}`).join(", "));
        check("slow", `seed ${seed}: the page has no error`, session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
      } finally {
        await browser.close();
        await server.stop();
      }
    }
  },

  // 3. The dead screen: 4 carriers, 3 spare bodies and one fast player for 3 minutes.
  async deadscreen() {
    for (const seed of SEEDS) {
      const server = await startServer({ carriers: 4, spare: 3, helpers: 0, seed });
      const browser = await launch();
      try {
        const session = await open(browser);
        const buttons = new Set();
        const final = await playNew(session, {
          limit: 180,
          done: () => false,
          each: async (state) => {
            buttons.add(state.button);
          },
        });
        console.log(`  seed ${seed}: ${final.locks} locks, ${final.stage - 1} crossings, ${final.food} food, buttons ${[...buttons].join(" ")}, the longest time with no guide and no bright button ${session.longestIdle.toFixed(1)} s`);
        check("deadscreen", `seed ${seed}: the player always has a guide or a bright button`, session.longestIdle < 1.05, `${session.longestIdle.toFixed(1)} s`);
        check("deadscreen", `seed ${seed}: the page has no error`, session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
      } finally {
        await browser.close();
        await server.stop();
      }
    }
  },

  // 4. My bodies: a player locks 5 bodies, takes a new name, and loads the page again. All
  // 5 bodies have the new name, and the panel shows 5 bodies and the walks.
  async bodies() {
    for (const seed of SEEDS) {
      const server = await startServer({ helpers: 0, seed });
      const browser = await launch();
      try {
        const session = await open(browser);
        const before = await session.state();
        await playNew(session, { limit: 240, done: (state) => state.locks >= 5 });
        // The bodies of my person, as the page sees them.
        const mine = () =>
          session.page.evaluate(() => {
            const { world } = window.colony;
            return [...world.locked.values()].filter((body) => body.owner === world.person && !body.helper).map((body) => body.name);
          });
        const locked = await mine();
        // A tap on my name opens the panel. The button of the panel gives a new name.
        await session.tapOn("me");
        await session.page.waitForFunction(() => !document.getElementById("panel").hidden);
        await session.tapOn("panelNew");
        await sleep(800);
        const name = (await session.state()).name;
        // The page loads again, with the same local storage.
        await session.page.reload();
        await session.page.waitForFunction(() => window.colony && window.colony.world.ready);
        await sleep(1500);
        const after = await mine();
        const again = await session.state();
        await session.tapOn("me");
        await session.page.waitForFunction(() => document.getElementById("panelBodies").textContent !== "0", null, { timeout: 5000 }).catch(() => {});
        await sleep(2500);
        const panel = await session.page.evaluate(() => ({
          name: document.getElementById("panelName").textContent,
          bodies: Number(document.getElementById("panelBodies").textContent),
          food: Number(document.getElementById("panelFood").textContent),
          walks: Number(document.getElementById("panelWalks").textContent),
        }));
        if (seed === SEEDS[0]) await session.shot(path.join(SHOTS, "name-panel.jpg"));
        console.log(`  seed ${seed}: ${locked.length} bodies of "${before.name}", new name "${name}", after the load: ${after.length} bodies, the panel ${JSON.stringify(panel)}`);
        check("bodies", `seed ${seed}: the player locked 5 bodies`, locked.length >= 5, `${locked.length}`);
        check("bodies", `seed ${seed}: after the load, all the bodies have the new name`, after.length === locked.length && after.every((other) => other === name) && name !== before.name, after.join(", "));
        check("bodies", `seed ${seed}: the page has the new name after the load`, again.name === name, again.name);
        check("bodies", `seed ${seed}: the panel shows the bodies and the walks`, panel.name === name && panel.bodies === locked.length && panel.walks >= 0, JSON.stringify(panel));
        check("bodies", `seed ${seed}: the page has no error`, session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
      } finally {
        await browser.close();
        await server.stop();
      }
    }
  },

  // 5. Two browsers: the same records, the same story, and the same marks of the open cells.
  async two() {
    const server = await startServer({ helpers: 0, seed: SEEDS[0] });
    const browser = await launch();
    try {
      const one = await open(browser);
      const two = await open(browser);
      // The marks of the open cells: each open cell with its gain, and the cells that are bright.
      const marks = (session) =>
        session.page.evaluate(() => {
          const { world } = window.colony;
          const open = [...world.open].sort((a, b) => a[0] - b[0]);
          return { open, bright: open.filter(([, gain]) => gain >= world.openBest).map(([cell]) => cell), spare: world.spare };
        });
      let compared = 0;
      let same = 0;
      await Promise.all([
        playNew(one, { limit: 300, done: (state) => state.stage >= 3 }),
        playNew(two, {
          limit: 300,
          done: (state) => state.stage >= 3,
          each: async () => {
            const [a, b] = await Promise.all([marks(one), marks(two)]);
            compared++;
            if (JSON.stringify(a) === JSON.stringify(b)) same++;
          },
        }),
      ]);
      await sleep(1500);
      const [a, b] = [await one.state(), await two.state()];
      const record = a.records.find((other) => other.id === 1);
      for (const session of [one, two]) await session.tapOn("storyButton");
      await Promise.all([one, two].map((session) => session.page.waitForFunction(() => window.colony.story.state().phase === "play" && window.colony.story.info, null, { timeout: 10000 })));
      const stories = await Promise.all([one, two].map((session) => session.page.evaluate(() => window.colony.story.data())));
      console.log(`  the marks of the open cells were the same in ${same} of ${compared} looks`);
      check("two", "the two players see the same records", JSON.stringify(a.records) === JSON.stringify(b.records), a.records.map((r) => `river ${r.id}: ${r.names.map((n) => `${n.name} ${n.bodies}`).join(", ")}`).join("; "));
      check("two", "a record has the names of the two players", record && [a.name, b.name].every((name) => record.names.some((entry) => entry.name === name && entry.bodies > 0)));
      check("two", "the two players see the same story", JSON.stringify(stories[0]) === JSON.stringify(stories[1]), `${stories[0].locks.length} locks`);
      // A look can fall between two messages of the server: one page has the new open
      // cells, the other not yet. Most of the looks must be the same.
      check("two", "the two players see the same marks of the open cells", compared > 0 && same / compared >= 0.9, `${same} of ${compared}`);
      check("two", "the pages have no error", one.errors.length + two.errors.length === 0, [...one.errors, ...two.errors].slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 6. A long world: 20 fast clients for 20 minutes. Then a browser opens the game and the
  // story: the frame time, the size of the first messages and the size of the picture.
  async longworld() {
    const minutes = Number(process.env.LONG_MINUTES || 20);
    const server = await startServer({ helpers: 0, seed: SEEDS[0], save: path.join(root, "tmp/long-world.bin") });
    try {
      // The young world, for a comparison.
      let browser = await launch();
      let session = await open(browser);
      await sleep(3000);
      const young = { frames: await frameTime(session), rivers: (await session.page.evaluate(() => window.colony.world.grid.rivers.length)) };
      await browser.close();

      const result = await crowd(20, minutes, (...words) => console.log("  ", ...words));
      console.log(`  20 fast clients, ${minutes} minutes: ${result.crossed} crossings`);

      browser = await launch();
      const sizes = [];
      session = await open(browser, "", false, null);
      // The page opened before the count: open it again with the count.
      const counter = await countMessages(session);
      await session.page.reload();
      await session.page.waitForFunction(() => window.colony && window.colony.world.ready);
      await sleep(4000);
      sizes.push(...counter);
      const world = await session.page.evaluate(() => ({ rivers: window.colony.world.grid.rivers.length, rows: window.colony.world.grid.rows, locked: window.colony.world.locked.size, stage: window.colony.world.stage }));
      const old = { frames: await frameTime(session) };
      const largest = [...sizes].sort((a, b) => b - a);
      await session.tapOn("storyButton");
      await session.page.waitForFunction(() => window.colony.story.state().phase === "play");
      const story = await session.page.evaluate(() => window.colony.story.state());
      await session.tapOn("storyClose");
      await session.page.waitForFunction(() => window.colony.story.state().phase === "end");
      await sleep(3000);
      await session.shot(path.join(SHOTS, "story-long-world.jpg"));
      const picture = await session.page.evaluate(async () => {
        const result = await window.colony.picture();
        return { bytes: Math.floor(((result.data.length - result.data.indexOf(",") - 1) * 3) / 4), parts: window.colony.story.pictureParts, names: result.names.length };
      });
      console.log(`  the young world (${young.rivers} rivers): frame time ${JSON.stringify(young.frames)}`);
      console.log(`  the long world (${world.stage - 1} crossings, ${world.rivers} rivers, ${world.rows} rows, ${world.locked} locked bodies): frame time ${JSON.stringify(old.frames)}`);
      console.log(`  the first messages: ${largest.slice(0, 3).join(", ")} bytes, all ${sizes.reduce((a, b) => a + b, 0)} bytes in ${sizes.length} messages`);
      console.log(`  the story: ${story.total} bodies in ${story.seconds} s. The picture: ${picture.bytes} bytes, ${picture.parts} parts, ${picture.names} names`);
      check("longworld", "the colony crossed 20 rivers or more", result.crossed >= 20, `${result.crossed}`);
      check("longworld", "the frame time does not increase in the long world", old.frames.median <= young.frames.median * 1.25, `${young.frames.median} ms and ${old.frames.median} ms`);
      check("longworld", "the story takes 40 seconds at the most", story.seconds <= 40, `${story.seconds} s`);
      check("longworld", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
      await browser.close();
    } finally {
      await server.stop();
    }
  },

  // The screenshots of section 5.3.
  async shots() {
    const shot = (session, name) => session.shot(path.join(SHOTS, `${name}.jpg`));
    const server = await startServer({ helpers: 0, seed: SEEDS[0] });
    const browser = await launch();
    try {
      const session = await open(browser);
      const taken = new Set();
      const once = async (name, ok) => {
        if (!ok || taken.has(name)) return;
        taken.add(name);
        await shot(session, name);
      };
      let stage = 1;
      let crossedAt = null;
      await playNew(session, {
        limit: Number(process.env.SHOT_SECONDS || 360),
        done: () => taken.size >= 12,
        each: async (state, seconds) => {
          const guide = await session.page.evaluate(() => {
            const current = window.colony.player.current;
            const { world } = window.colony;
            const gains = [...world.open.values()];
            return { kind: current ? current.kind : null, mark: Boolean(window.colony.view().mark), wider: gains.some((gain) => gain > 0) && gains.some((gain) => gain < world.openBest) };
          });
          await once("workers", seconds > 4 && state.carriers > 0 && state.spare > 0);
          await once(`button-${state.button}`, true);
          await once(`guide-${guide.kind}`, guide.kind !== null && guide.mark);
          await once("wider", guide.wider);
          if (state.stage > stage) {
            stage = state.stage;
            crossedAt = seconds;
          }
          // Some seconds after a crossing: the carriers carry the eggs to the new nest.
          await once("nest-move", crossedAt !== null && seconds - crossedAt > 7 && stage >= 2);
        },
      });
      console.log(`  screenshots: ${[...taken].sort().join(", ")}`);
    } finally {
      await browser.close();
      await server.stop();
    }

    // Lands 5 to 8 and the story of a world with 10 rivers: a world that the script
    // tmp/make-long.exs made. Without the file, these screenshots are not made.
    const long = path.join(root, "tmp/long10.bin");
    const copy = path.join(root, "tmp/long10-play.bin");
    try {
      copyFileSync(long, copy);
    } catch (_) {
      console.log("  no tmp/long10.bin: no screenshot of lands 5 to 8 and of the story");
      return;
    }
    const server2 = await startServer({ save: copy, keep: true });
    const browser2 = await launch();
    try {
      const session = await open(browser2);
      await sleep(2000);
      // The camera looks at lands 5 to 8 from high above.
      await session.page.evaluate(() => {
        const { world, camera } = window.colony;
        const grid = world.grid;
        const z = ((grid.rivers[5].start + grid.rivers[8].start) / 2) * 0.866;
        window.colony.freeze(true);
        Object.assign(camera, { x: 30, z: z - 8, height: 46, distance: 58, turn: 0 });
      });
      await session.shot(path.join(SHOTS, "lands-5-to-8.jpg"));
      await session.page.evaluate(() => window.colony.freeze(false));
      await session.tapOn("storyButton");
      await session.page.waitForFunction(() => window.colony.story.state().phase === "play");
      await sleep(6000);
      await session.shot(path.join(SHOTS, "story-10-rivers-play.jpg"));
      await session.tapOn("storyClose");
      await sleep(3500);
      await session.shot(path.join(SHOTS, "story-10-rivers.jpg"));
      console.log("  screenshots: lands-5-to-8, story-10-rivers-play, story-10-rivers");
    } finally {
      await browser2.close();
      await server2.stop();
    }
  },
};

const names = process.argv.slice(2).length > 0 ? process.argv.slice(2) : Object.keys(tests);
for (const name of names) {
  if (!tests[name]) throw new Error(`There is no test "${name}".`);
  console.log(`\nTest "${name}"`);
  try {
    await tests[name]();
  } catch (error) {
    check(name, `the test runs to its end (${error.message.split("\n")[0]})`, false);
  }
}
const failed = results.filter((result) => !result.ok);
writeFileSync(path.join(root, `tmp/play-results-${names.join("-")}.json`), JSON.stringify(results, null, 1));
console.log(`\n${results.length - failed.length} of ${results.length} targets are met.`);
process.exit(failed.length === 0 ? 0 : 1);
