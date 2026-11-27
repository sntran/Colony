// The guide of the page for a snapshot of the server. The test test/guide_test.exs runs
// this file and compares the result with the guide of the server.
//
//     node test/js/guide.mjs SNAPSHOT_FILE CASES_JSON
//
// Each case is { x, z, carry, last }: a body of the player of the snapshot. The result is
// one line of JSON: for each case, { kind, cell } or null.

import { readFileSync } from "node:fs";
import { World } from "../../priv/static/js/state.js";
import { Guide } from "../../priv/static/js/guide.js";

const [file, cases] = process.argv.slice(2);
const bytes = readFileSync(file);
const world = new World();
world.snapshot(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
world.update(0);
const guide = new Guide(world);
const result = JSON.parse(cases).map(({ x, z, carry, last }) => {
  const me = { alive: true, x, z, carry };
  const target = guide.guide(me, last);
  return target ? { kind: target.kind, cell: target.cell } : null;
});
console.log(JSON.stringify(result));
