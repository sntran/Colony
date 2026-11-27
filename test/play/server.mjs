// Starts and stops the game server for a play test. Each test gets a new world.

import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import path from "node:path";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const PORT = process.env.PORT || "4000";
export const BASE = `http://localhost:${PORT}/`;

// options: { workers, helpers, seed, save, keep }. `save` is the path of the save file.
// With `keep`, the server loads the save file that is there.
export async function startServer(options = {}) {
  const save = options.save || path.join(root, "tmp/play-world.bin");
  mkdirSync(path.dirname(save), { recursive: true });
  if (!options.keep) rmSync(save, { force: true });
  const env = {
    ...process.env,
    PORT,
    COLONY_WORKERS: String(options.workers ?? 30),
    COLONY_HELPERS: String(options.helpers ?? 0),
    COLONY_SEED: String(options.seed ?? process.env.COLONY_SEED ?? 2027),
    COLONY_SAVE_FILE: save,
  };
  if (await answers()) throw new Error(`A server is on port ${PORT} already. Stop it first.`);
  const child = spawn("mix", ["phx.server"], { cwd: root, env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
  let log = "";
  child.stdout.on("data", (data) => (log += data));
  child.stderr.on("data", (data) => (log += data));
  const end = Date.now() + 90000;
  while (!(await answers())) {
    if (Date.now() > end) throw new Error(`The server did not start.\n${log}`);
    await sleep(300);
  }
  return {
    save,
    log: () => log,
    // The server saves the world when it stops. The function returns when the port is free.
    async stop() {
      const signal = (name) => {
        try {
          process.kill(-child.pid, name);
        } catch (_) {
          // The process is not there.
        }
        // The VM can be in a process group of its own.
        spawnSync("pkill", [`-${name.slice(3)}`, "-f", "phx.server"]);
      };
      signal("SIGTERM");
      const limit = Date.now() + 10000;
      while ((await answers()) && Date.now() < limit) await sleep(200);
      if (await answers()) {
        signal("SIGKILL");
        while (await answers()) await sleep(200);
      }
      await sleep(500);
    },
  };
}

const sleep = (time) => new Promise((resolve) => setTimeout(resolve, time));

// True if a server answers on the port.
async function answers() {
  try {
    return (await fetch(BASE, { signal: AbortSignal.timeout(2000) })).ok;
  } catch (_) {
    return false;
  }
}
