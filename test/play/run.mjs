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
