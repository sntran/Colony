// The play tests of plan 0003, section 5.3.
//
//     node test/play/run.mjs [alone] [story] [carry] [helpers] [two] [crowd] [sound] [moments]
//
// With no name, all the tests run. Each test starts the server with a new world and
// stops it. Stop your server first: the tests use port 4000.
//
// The tests play in Chromium at 390 x 844 with real touch events. The script of the new
// player is in newplayer.mjs. The test "crowd" has no browser: see crowd.mjs. The test
// "story" uses the world of the test "alone": run "alone" first. The test "moments"
// makes the screenshots of the report.

import { mkdirSync, writeFileSync, existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { startServer } from "./server.mjs";
import { launch, open, playNew, BASE } from "./browser.mjs";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const SHOTS = path.join(root, "docs/playtests/0003");
mkdirSync(SHOTS, { recursive: true });

// The row "Random" of section 4.5 of the plan: the most bodies for each width of a river.
const RANDOM = { 5: 5, 6: 6, 7: 7, 8: 8, 9: 10, 10: 14, 11: 18, 12: 22, 13: 27, 14: 30, 16: 42, 17: 47, 18: 51 };

const results = [];
function check(test, text, ok, value = "") {
  results.push({ test, text, ok });
  console.log(`${ok ? "met     " : "NOT MET "} ${text}${value === "" ? "" : `: ${value}`}`);
}
const sleep = (time) => new Promise((resolve) => setTimeout(resolve, time));

// Walks along the way of the page to a goal ("pile" or "nest") until `done(state)`.
async function follow(session, kind, done, limit = 120) {
  const end = Date.now() + limit * 1000;
  for (;;) {
    const state = await session.state();
    if (done(state)) break;
    if (Date.now() > end) throw new Error(`no way to the ${kind} in ${limit} seconds`);
    const aim = await session.page.evaluate((goal) => {
      const { world, guide } = window.colony;
      const route = guide.route(goal, world.me.x, world.me.z);
      return route ? [route.aimX - world.me.x, route.aimZ - world.me.z] : null;
    }, kind);
    if (aim && Math.hypot(aim[0], aim[1]) > 0.01) {
      const length = Math.hypot(aim[0], aim[1]);
      // On the screen, right is the -x direction of the world.
      await session.stick(-aim[0] / length, aim[1] / length);
    }
    await session.page.waitForTimeout(80);
  }
  await session.stick(0, 0);
}

const tests = {
  // 1. A new player alone, 30 workers, no helper.
  async alone() {
    const server = await startServer({ workers: 30, helpers: 0 });
    const browser = await launch();
    try {
      const session = await open(browser);
      const result = { crossings: [], longestWait: 0, longestGap: 0, lockTimes: [] };
      let waitFrom = null;
      let lastLock = { count: 0, at: 0 };
      let stage = 1;
      let lastPrint = 0;
      const final = await playNew(session, {
        limit: 30 * 60,
        done: (state) => state.complete,
        each: async (state, seconds) => {
          // The longest time with no spare body, while a bridge is not complete.
          if (state.spare === 0 && state.stage <= 4) {
            if (waitFrom === null) waitFrom = seconds;
            result.longestWait = Math.max(result.longestWait, seconds - waitFrom);
          } else {
            waitFrom = null;
          }
          // The longest time between two locks of the player.
          if (state.locks !== lastLock.count) {
            if (state.stage === 1) result.lockTimes.push(Number(seconds.toFixed(1)));
            lastLock = { count: state.locks, at: seconds };
          } else if (state.stage <= 4) {
            result.longestGap = Math.max(result.longestGap, seconds - lastLock.at);
          }
          if (state.stage !== stage) {
            stage = state.stage;
            const record = state.records.find((other) => other.id === stage - 1);
            result.crossings.push({ river: stage - 1, seconds: Math.round(seconds), bodies: record.bodies, width: record.width, random: RANDOM[record.width], left: record.left, size: record.size, spare: state.spare });
            console.log("  crossing", JSON.stringify(result.crossings[result.crossings.length - 1]));
            lastLock.at = seconds;
          }
          if (seconds - lastPrint >= 60) {
            lastPrint = seconds;
            console.log(`  ${Math.round(seconds)} s: river ${state.stage}, ${state.locks} locks, ${state.spare} spare, ${state.food} food, wait ${result.longestWait.toFixed(1)} s`);
          }
        },
      });
      result.firstFood = final.times.firstFood === null ? null : Number(((final.times.firstFood - final.times.load) / 1000).toFixed(1));
      result.complete = final.complete;
      result.locks = final.locks;
      result.refusedLocks = final.noLocks;
      result.corrections = final.corrections;
      result.errors = session.errors.slice(0, 5);
      result.sound = final.sound;
      result.locked = final.locked;
      writeFileSync(path.join(root, "tmp/play-alone.json"), JSON.stringify(result, null, 1));
      console.log(JSON.stringify(result));
      check("alone", "the first food is at the nest in less than 60 seconds from the load", result.firstFood !== null && result.firstFood < 60, `${result.firstFood} s`);
      check("alone", "the player completes the four crossings", result.crossings.length === 4, result.crossings.map((c) => `river ${c.river}: ${c.seconds} s, ${c.bodies} bodies`).join("; "));
      check("alone", "the bodies of each bridge are not more than the row Random", result.crossings.length === 4 && result.crossings.every((c) => c.bodies <= c.random), result.crossings.map((c) => `${c.bodies} of ${c.random} at width ${c.width}`).join("; "));
      check("alone", "the player never waits more than 20 seconds for a spare body", result.longestWait <= 20, `${result.longestWait.toFixed(1)} s`);
      check("alone", "the world is complete", result.complete === true);
      // Test 7, sound: the page counts the notes that it plays.
      check("alone", "sound: the page played one note for each lock", final.sound.running && final.sound.locks === final.locked && final.sound.dropped === 0, `${final.sound.locks} notes, ${final.locked} locks`);
      check("alone", "sound: the page played the song of the bridge at each crossing", final.sound.songs === 4 && final.sound.chords === 4, `${final.sound.songs} songs with ${final.sound.songNotes} notes, ${final.sound.chords} chords`);
      check("alone", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
      // When the world is complete, the page shows the story one time.
      await session.page.waitForFunction(() => window.colony.story.state().phase !== "off", null, { timeout: 15000 }).catch(() => {});
      check("alone", "the page shows the story when the world is complete", (await session.state()).story.phase !== "off");
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 6. The story: "/?story=1" after test 1. The server loads the world of that test.
  async story() {
    const save = path.join(root, "tmp/play-world.bin");
    if (!existsSync(save)) throw new Error('there is no world of the test "alone"');
    const server = await startServer({ workers: 30, helpers: 0, keep: true });
    const browser = await launch();
    try {
      const session = await open(browser, "&story=1");
      await session.page.waitForFunction(() => window.colony.story.state().phase === "play", null, { timeout: 15000 });
      const start = Date.now();
      await session.page.waitForFunction(() => window.colony.story.state().shown >= window.colony.story.state().total * 0.45, null, { timeout: 60000 });
      await session.shot(`${SHOTS}/23-story-the-bodies-appear.jpg`);
      await session.page.waitForFunction(() => window.colony.story.state().phase === "end", null, { timeout: 60000 });
      const seconds = (Date.now() - start) / 1000;
      await sleep(3000);
      await session.shot(`${SHOTS}/24-story-the-world-from-above.jpg`);
      const story = await session.page.evaluate(() => ({ order: window.colony.story.order, data: window.colony.story.data(), state: window.colony.story.state(), players: window.colony.world.players.size }));
      const sorted = story.order.every((n, index) => index === 0 || n > story.order[index - 1]);
      const names = story.data.names.map((entry) => entry.name);
      console.log(`  ${story.order.length} bodies in ${seconds.toFixed(1)} s. Names: ${story.data.names.map((entry) => `${entry.name} ${entry.bodies} bodies ${entry.food} food`).join(", ")}`);

      // The picture: a PNG file with the date and the names.
      const picture = await session.page.evaluate(() => window.colony.picture());
      const png = Buffer.from(picture.data.split(",")[1], "base64");
      writeFileSync(path.join(root, "tmp/play-story-picture.png"), png);
      const isPng = png.subarray(0, 8).toString("hex") === "89504e470d0a1a0a";
      const size = [png.readUInt32BE(16), png.readUInt32BE(20)];
      // The button saves the same picture as a file.
      const download = session.page.waitForEvent("download", { timeout: 15000 });
      await session.tapOn("storySave");
      const file = await download.catch(() => null);
      const fileName = file ? file.suggestedFilename() : "";

      check("story", "the story has no body in the world", story.players === 0);
      check("story", "all the bodies appear, in the order of their locks", story.order.length === story.data.locks.length && story.order.length > 0 && sorted, `${story.order.length} of ${story.data.locks.length} bodies`);
      check("story", "the story plays in 20 to 40 seconds", seconds >= 19 && seconds <= 41, `${seconds.toFixed(1)} s`);
      check("story", "the picture is a PNG file with the date and the names", isPng && png.length > 20000 && picture.date !== "" && names.length > 0 && JSON.stringify(picture.names) === JSON.stringify(names), `${size[0]} x ${size[1]} pixels, ${Math.round(png.length / 1024)} KB, the date ${picture.date}, the names ${picture.names.join(", ")}`);
      check("story", "the button saves the picture as a PNG file", fileName.endsWith(".png"), fileName);
      check("story", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 7. Sound: no error if the browser gives no sound.
  async sound() {
    const server = await startServer({ workers: 30, helpers: 0 });
    const browser = await launch();
    try {
      // A browser with no Web Audio API.
      const silent = await open(browser, "", false, () => {
        delete window.AudioContext;
        delete window.webkitAudioContext;
      });
      await silent.page.waitForFunction(() => window.colony && window.colony.world.ready);
      const end = await playNew(silent, { limit: 120, done: (state) => state.stage >= 2 });
      console.log(`  with no sound: ${end.locks} locks, counts ${JSON.stringify(end.sound)}`);
      check("sound", "with no sound in the browser, the game plays and the page has no error", end.stage >= 2 && silent.errors.length === 0 && end.sound.locks === 0 && !end.sound.running, silent.errors.slice(0, 2).join(" | "));
      // The button stops and starts the sound.
      const session = await open(browser);
      await session.touch.tap(3, 60, 800);
      const on = await session.page.evaluate(() => ({ on: window.colony.sound.on, running: window.colony.sound.context && window.colony.sound.context.state }));
      await session.tapOn("soundButton");
      const off = await session.page.evaluate(() => window.colony.sound.on);
      await session.tapOn("soundButton");
      const again = await session.page.evaluate(() => window.colony.sound.on);
      check("sound", "the sound starts at the first touch", on.on && on.running === "running", `${on.running}`);
      check("sound", "the button stops and starts the sound", off === false && again === true);
      check("sound", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // The screenshots of the report: each moment of a lock and of a crossing, and each land.
  async moments() {
    const server = await startServer({ workers: 30, helpers: 0 });
    const browser = await launch();
    try {
      const session = await open(browser);
      const page = session.page;
      await session.shot(`${SHOTS}/01-land-0-the-nest.jpg`);
      const taken = new Set();
      let locks = 0;
      let land = 0;
      let showingSince = null;
      let cardSince = null;
      await playNew(session, {
        limit: 15 * 60,
        done: (state) => state.stage >= 5 && taken.has("card5"),
        each: async (state, seconds) => {
          // The moment of a lock: the body goes down and the light flies, then the name.
          if (state.locks > locks) {
            locks = state.locks;
            if (locks === 2 || locks === 9) {
              await sleep(170);
              await session.shot(`${SHOTS}/0${locks === 2 ? 2 : 4}-lock-${locks === 2 ? "the-light-flies" : "on-river-2"}.jpg`);
            }
            if (locks === 3) {
              await sleep(520);
              await session.shot(`${SHOTS}/03-lock-the-name-and-the-ring.jpg`);
            }
          }
          // The moment of a crossing: the full bridge, then the record card, then the
          // light of the next pile and the arrow.
          if (state.moment.showing && showingSince === null) showingSince = seconds;
          if (showingSince !== null && seconds - showingSince > 1.3 && !taken.has(`bridge${state.stage}`) && state.moment.showing) {
            taken.add(`bridge${state.stage}`);
            await session.shot(`${SHOTS}/${String(3 + state.stage * 2).padStart(2, "0")}-crossing-${state.stage - 1}-the-full-bridge.jpg`);
          }
          if (!state.moment.showing) showingSince = null;
          if (state.moment.card && cardSince === null) cardSince = seconds;
          if (!state.moment.card) cardSince = null;
          if (cardSince !== null && seconds - cardSince > 2.6 && !taken.has(`card${state.stage}`)) {
            taken.add(`card${state.stage}`);
            await session.shot(`${SHOTS}/${String(4 + state.stage * 2).padStart(2, "0")}-crossing-${state.stage - 1}-the-record-and-the-next-pile.jpg`);
          }
          // Each land.
          if (state.land > land && !state.moment.showing && !state.moment.flight) {
            land = state.land;
            await session.shot(`${SHOTS}/${String(14 + land).padStart(2, "0")}-land-${land}.jpg`);
          }
        },
      });
      // After the last crossing, the script has no work. The player goes to land 4.
      const end = Date.now() + 25000;
      while (Date.now() < end && (await session.state()).land !== 4) {
        await session.stick(0, 1);
        await sleep(100);
      }
      await session.stick(0, 0);
      if ((await session.state()).land === 4) {
        land = 4;
        await session.shot(`${SHOTS}/18-land-4.jpg`);
      }
      // The story opens when the world is complete.
      await page.waitForFunction(() => window.colony.story.state().phase === "play", null, { timeout: 90000 });
      await page.waitForFunction(() => window.colony.story.state().shown >= window.colony.story.state().total * 0.7, null, { timeout: 60000 });
      await session.shot(`${SHOTS}/19-story-after-the-last-crossing.jpg`);
      check("moments", "the screenshots of the moments are in docs/playtests/0003", taken.size >= 8 && land === 4, `${[...taken].join(", ")}, ${land} lands`);
      check("moments", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 2. A player who never locks, with 3 helpers. The player carries food 5 times.
  async carry() {
    const server = await startServer({ workers: 30, helpers: 3 });
    const browser = await launch();
    try {
      const session = await open(browser);
      // The helpers build the bridge of river 1. Then a body can walk to pile 1.
      await session.page.waitForFunction(() => window.colony.world.stage >= 2, null, { timeout: 180000 });
      const start = await session.state();
      for (let trip = 1; trip <= 5; trip++) {
        await follow(session, "pile", (state) => state.carry);
        if (trip === 1) await session.shot(`${SHOTS}/20-a-player-carries-food.jpg`);
        await follow(session, "nest", (state) => !state.carry);
        console.log(`  trip ${trip}: food at the nest ${(await session.state()).food}`);
      }
      const now = await session.state();
      // The record of the next crossing counts the food.
      await session.page.waitForFunction((stage) => window.colony.world.stage > stage, now.stage, { timeout: 600000 });
      await sleep(1500);
      const final = await session.state();
      const mine = final.records.flatMap((record) => record.names.filter((entry) => entry.name === final.name).map((entry) => ({ river: record.id, ...entry })));
      const food = mine.reduce((sum, entry) => sum + entry.food, 0);
      const story = await session.page.evaluate(() => window.colony.net.story());
      const inStory = story.names.find((entry) => entry.name === final.name);
      console.log("  records of the player:", JSON.stringify(mine), "story:", JSON.stringify(inStory));
      check("carry", "the player carried food 5 times and never locked", final.locks === 0 && final.food >= start.food + 50);
      check("carry", "the records count the food of the player: 50 units, 0 bodies", food === 50 && mine.every((entry) => entry.bodies === 0), JSON.stringify(mine));
      check("carry", "the story counts the food of the player", inStory && inStory.food === 50 && inStory.bodies === 0);
      check("carry", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 3. One player and 3 helpers.
  async helpers() {
    const server = await startServer({ workers: 30, helpers: 3 });
    const browser = await launch();
    try {
      const session = await open(browser);
      const final = await playNew(session, { limit: 600, done: (state) => state.stage >= 3 });
      const log = await session.page.evaluate(() => window.colony.player.lockLog);
      const record = final.records.find((other) => other.id === 1);
      const names = record ? record.names : [];
      const far = log.filter((lock) => lock.distance > 3.05);
      console.log("  record of river 1:", JSON.stringify(record));
      console.log("  the distances to the new bodies:", log.map((lock) => lock.distance.toFixed(1)).join(" "));
      await session.shot(`${SHOTS}/21-a-player-and-helpers.jpg`);
      check("helpers", "the record of river 1 has the name of the player and names of helpers", names.some((entry) => entry.name === final.name && !entry.helper && entry.bodies > 0) && names.some((entry) => entry.helper));
      check("helpers", "each lock of the player gives a new body 3 cells or less from the locked body", log.length > 0 && far.length === 0, `${log.length} locks, ${far.length} with a larger distance, the largest is ${Math.max(...log.map((lock) => lock.distance)).toFixed(1)} cells`);
      check("helpers", "the page has no error", session.errors.length === 0, session.errors.slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 4. Two browsers: the two players see the same record and the same story.
  async two() {
    const server = await startServer({ workers: 30, helpers: 0 });
    const browser = await launch();
    try {
      const one = await open(browser);
      const two = await open(browser);
      await Promise.all([
        playNew(one, { limit: 300, done: (state) => state.stage >= 2 }),
        playNew(two, { limit: 300, done: (state) => state.stage >= 2 }),
      ]);
      await sleep(1500);
      const [a, b] = [await one.state(), await two.state()];
      const record = a.records.find((other) => other.id === 1);
      console.log("  record:", JSON.stringify(record));
      await one.shot(`${SHOTS}/22-two-players-the-story.jpg`);
      // The story: each page opens it. The data of the story is the locks and the names.
      for (const session of [one, two]) await session.tapOn("storyButton");
      await Promise.all([one, two].map((session) => session.page.waitForFunction(() => window.colony.story.state().phase === "play" && window.colony.story.info, null, { timeout: 10000 })));
      const stories = await Promise.all([one, two].map((session) => session.page.evaluate(() => window.colony.story.data())));
      check("two", "the two players have different names", a.name !== b.name);
      check("two", "the two players see the same record", record && JSON.stringify(a.records) === JSON.stringify(b.records));
      check("two", "the record has the names of the two players", record && [a.name, b.name].every((name) => record.names.some((entry) => entry.name === name && entry.bodies > 0)), record && record.names.map((entry) => `${entry.name} ${entry.bodies}`).join(", "));
      check("two", "the two players see the same story", stories[0] && JSON.stringify(stories[0]) === JSON.stringify(stories[1]), stories[0] ? `${stories[0].locks.length} locks` : "the page has no story");
      check("two", "the pages have no error", one.errors.length + two.errors.length === 0, [...one.errors, ...two.errors].slice(0, 2).join(" | "));
    } finally {
      await browser.close();
      await server.stop();
    }
  },

  // 5. Twenty new players, with no browser.
  async crowd() {
    const server = await startServer({ workers: 30, helpers: 0 });
    try {
      const { run } = await import("./crowd.mjs");
      const result = await run(20, 40, (...words) => console.log(" ", ...words));
      writeFileSync(path.join(root, "tmp/play-crowd.json"), JSON.stringify(result, null, 1));
      console.log(`  the world is complete after ${result.seconds} s. First food after ${result.firstFood && result.firstFood.toFixed(1)} s. The longest time with no spare body: ${result.longestWait.toFixed(1)} s.`);
      for (const player of result.players) console.log(`  ${player.name}: ${player.locks} locks, ${player.food} food`);
      check("crowd", "20 new players complete the four crossings", result.complete && result.crossings.length === 4, result.crossings.map((c) => `river ${c.river}: ${c.seconds} s, ${c.bodies} bodies`).join("; "));
      console.log(`  ${result.noLock} of ${result.clients} clients got no lock.`);
    } finally {
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
console.log(`\n${results.length - failed.length} of ${results.length} targets are met.`);
void readFileSync;
void BASE;
process.exit(failed.length === 0 ? 0 : 1);
