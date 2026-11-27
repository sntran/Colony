// The play tests of plan 0004, section 5.3, in a browser.
//
//     node test/play/run.mjs [deadscreen] [two] [slow] [bodies] [longworld] [moments]
//
// With no name, all the tests run. Each test starts the server with a new world and stops
// it. Stop your server first: the tests use port 4000. Test 2 (fast players with no
// browser) is test/play/fast.mjs.
//
// The tests play in Chromium at 390 x 844 with real touch events. The script of the new
// player is in newplayer.mjs: it knows only what a person sees.

import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { startServer } from "./server.mjs";
import { launch, open, playNew } from "./browser.mjs";

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

const tests = {
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
