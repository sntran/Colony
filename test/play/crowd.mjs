// Play test 5 of plan 0003: twenty new players, with no browser.
//
// Start the server first, with a new world. Then:
//
//     node test/play/crowd.mjs [clients] [minutes]
//
// Each client is a real connection to the server. It uses the code of the page for the
// world, for the body of the player and for the arrow (priv/static/js), and the script of
// the new player (newplayer.mjs). It has no picture: it calculates what a person sees on
// a screen of 390 x 844 from the camera of a player.

import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { World } from "../../priv/static/js/state.js";
import { Guide } from "../../priv/static/js/guide.js";
import { Player } from "../../priv/static/js/player.js";
import { viewOf, project, PLAYER_CAMERA } from "../../priv/static/js/view.js";
import { NewPlayer } from "./newplayer.mjs";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const { Socket } = await import(pathToFileURL(path.join(root, "deps/phoenix/priv/static/phoenix.mjs")).href);
void createRequire;

const BASE = (process.env.COLONY_URL || "http://localhost:4000/").replace(/^http/, "ws").replace(/\/$/, "");
const WIDTH = 390;
const HEIGHT = 844;

export class Client {
  constructor(name) {
    this.name = name;
    this.world = new World();
    this.world.me.name = name;
    this.guide = new Guide(this.world);
    this.script = new NewPlayer();
    this.stick = [0, 0];
    this.last = null;
    this.records = [];
    this.onRecord = null;
    this.socket = new Socket(`${BASE}/socket`, { transport: WebSocket });
    this.socket.connect();
    this.channel = this.socket.channel("world", { name });
    this.player = new Player(this.world, this.guide, {
      move: (buffer) => this.channel.push("m", buffer),
      lock: (cell, at) =>
        new Promise((resolve) => {
          this.channel
            .push("lock", { cell, at }, 3000)
            .receive("ok", (reply) => resolve(reply || {}))
            .receive("error", () => resolve(null))
            .receive("timeout", () => resolve(null));
        }),
    });
    this.channel.on("s", (buffer) => {
      this.world.snapshot(buffer);
      const mine = this.world.players.get(this.world.you);
      this.world.me.alive = Boolean(mine);
      if (mine) this.player.place(mine.tx, mine.tz);
    });
    this.channel.on("t", (buffer) => this.world.applyTick(buffer));
    this.channel.on("you", (message) => {
      if (typeof message.x === "number") this.player.correct(message, performance.now());
    });
    this.channel.on("record", (record) => {
      if (record.first && this.onRecord) this.onRecord(record);
      this.records = [record, ...this.records.filter((other) => other.id !== record.id)];
    });
    this.channel.join();
  }

  // What a person sees on the screen of a phone.
  view(now) {
    const { world, guide, player } = this;
    const me = world.me;
    const camera = { ...PLAYER_CAMERA, x: me.x, z: me.z + PLAYER_CAMERA.ahead };
    const { matrix } = viewOf(camera, WIDTH / HEIGHT);
    const onPage = (x, y, z) => {
      const at = project(matrix, x, y, z);
      return at ? [(at[0] * 0.5 + 0.5) * WIDTH, (0.5 - at[1] * 0.5) * HEIGHT] : null;
    };
    const arrow = guide.arrow(me, onPage, WIDTH, HEIGHT);
    return guide.view(me, player.ready(now), arrow, onPage, WIDTH, HEIGHT);
  }

  // One frame of the page: 30 frames each second.
  frame(dt, now) {
    const { world, player } = this;
    if (!world.ready || !world.me.alive) return;
    world.update(dt);
    world.takeNews();
    player.step(dt, this.stick[0], this.stick[1]);
    player.send(now);
  }

  // The script: 10 times each second.
  think(now) {
    const { world, player } = this;
    if (!world.ready || !world.me.alive) return;
    const me = world.me;
    const moved = this.last === null || Math.hypot(me.x - this.last[0], me.z - this.last[1]) > 0.03;
    this.last = [me.x, me.z];
    const action = this.script.step(this.view(now), moved, now);
    this.stick = action.stick;
    if (action.tap) player.lock(now, () => performance.now());
  }

  story() {
    return new Promise((resolve) => {
      this.channel.push("story", {}, 5000).receive("ok", resolve).receive("error", () => resolve(null)).receive("timeout", () => resolve(null));
    });
  }

  close() {
    this.socket.disconnect();
  }
}

// Runs the clients until the world is complete. Returns the result.
export async function run(count, minutes, log = console.log) {
  const clients = [];
  for (let n = 1; n <= count; n++) clients.push(new Client(`New ${String(n).padStart(2, "0")}`));
  const start = performance.now();
  const crossings = [];
  clients[0].onRecord = (record) => {
    const seconds = Math.round((performance.now() - start) / 1000);
    crossings.push({ river: record.id, seconds, bodies: record.bodies, width: record.width, left: record.left, size: record.size });
    log("crossing", JSON.stringify(crossings[crossings.length - 1]));
  };

  let last = performance.now();
  let firstFood = null;
  let longestWait = 0;
  let waitFrom = null;
  const frames = setInterval(() => {
    const now = performance.now();
    const dt = Math.min(0.25, (now - last) / 1000);
    last = now;
    for (const client of clients) client.frame(dt, now);
    const world = clients[0].world;
    if (world.ready) {
      const seconds = (now - start) / 1000;
      if (firstFood === null && world.foodNest > 0) firstFood = seconds;
      if (world.freeWorkers === 0 && world.stage <= 4) {
        if (waitFrom === null) waitFrom = seconds;
        longestWait = Math.max(longestWait, seconds - waitFrom);
      } else {
        waitFrom = null;
      }
    }
  }, 33);
  const thoughts = setInterval(() => {
    const now = performance.now();
    for (const client of clients) client.think(now);
  }, 100);
  const prints = setInterval(() => {
    const world = clients[0].world;
    const seconds = Math.round((performance.now() - start) / 1000);
    const locks = clients.reduce((sum, client) => sum + client.player.locks, 0);
    log(`  ${seconds} s: stage ${world.stage}, ${locks} locks, ${world.freeWorkers} spare, ${world.foodNest} food`);
  }, 30000);

  await new Promise((resolve) => {
    const check = setInterval(() => {
      const world = clients[0].world;
      if ((world.ready && world.complete) || performance.now() - start > minutes * 60000) {
        clearInterval(check);
        resolve();
      }
    }, 200);
  });
  clearInterval(frames);
  clearInterval(thoughts);
  clearInterval(prints);

  const seconds = Math.round((performance.now() - start) / 1000);
  const story = await clients[0].story();
  const food = new Map((story ? story.names : []).map((entry) => [entry.name, entry.food]));
  const players = clients.map((client) => ({
    name: client.name,
    locks: client.player.locks,
    food: food.get(client.name) || 0,
    corrections: client.player.corrections,
  }));
  const complete = clients[0].world.complete;
  for (const client of clients) client.close();
  return { clients: count, complete, seconds, firstFood, longestWait, crossings, players, noLock: players.filter((entry) => entry.locks === 0).length };
}

if (process.argv[1] && process.argv[1].endsWith("crowd.mjs")) {
  const result = await run(Number(process.argv[2] || 20), Number(process.argv[3] || 30));
  console.log(JSON.stringify(result, null, 1));
  console.log(result.complete && result.crossings.length === 4 ? "met     " : "NOT MET ", "the clients complete the four crossings");
  process.exit(result.complete ? 0 : 1);
}
