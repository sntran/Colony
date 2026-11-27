// Play test 2 of plan 0004: fast players with no browser.
//
//     node test/play/fast.mjs CLIENTS MINUTES SEED [PORT]
//
// The test starts a server with a new world of the seed on the port (4000 by default),
// runs the clients with the script of the new player, and writes the result to
// tmp/fast-CLIENTS-SEED.json. Each run uses a port of its own: runs can go at one time.

import { writeFileSync } from "node:fs";
import path from "node:path";

const [clients, minutes, seed, port = "4000"] = process.argv.slice(2);
process.env.PORT = port;
process.env.COLONY_URL = `http://localhost:${port}/`;
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const { startServer } = await import("./server.mjs");
const { run } = await import("./crowd.mjs");

const save = path.join(root, `tmp/fast-${clients}-${seed}.bin`);
const server = await startServer({ seed: Number(seed), save, port });
try {
  const result = await run(Number(clients), Number(minutes), (...words) => console.log(`[${clients}/${seed}]`, ...words));
  result.seed = Number(seed);
  writeFileSync(path.join(root, `tmp/fast-${clients}-${seed}.json`), JSON.stringify(result, null, 1));
  console.log(`[${clients}/${seed}] done: ${result.crossed} crossings in ${result.seconds} s, ${result.noLock} clients with no lock, ${result.noTrip} with no trip, idle ${result.longestIdle} s`);
} finally {
  await server.stop();
}
process.exit(0);
