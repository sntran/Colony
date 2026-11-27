// What the page tells a player: the cell for a lock, and the direction of the arrow.
//
// This file uses no page and no picture. A test player with no browser uses it also.

// The steps of the way that the arrow looks along.
const LOOK_STEPS = 9;

export class Guide {
  constructor(world) {
    this.world = world;
    this.fields = new Map();
  }

  // The open cell for a lock: an open cell that touches the cell of the body. If two open
  // cells touch it, the cell nearest to the direction (dx, dz) is used. Returns -1 if
  // no open cell touches the cell.
  target(x, z, dx, dz) {
    const world = this.world;
    const grid = world.grid;
    const here = grid.cellAt(x, z);
    if (here < 0 || world.open.size === 0) return -1;
    let best = -1;
    let bestScore = -Infinity;
    for (const cell of grid.neighbors(here)) {
      if (!world.open.has(cell)) continue;
      const cx = grid.x(cell) - x;
      const cz = grid.z(cell) - z;
      const score = (cx * dx + cz * dz) / (Math.hypot(cx, cz) || 1);
      if (score > bestScore) {
        bestScore = score;
        best = cell;
      }
    }
    return best;
  }

  // The goal of the arrow: "open", "nest", "pile" or null. The first rule that applies:
  //
  // - The colony has a spare body and an open cell: the nearest open cell.
  // - I carry food: the nest.
  // - The colony has no spare body: the nearest pile with food that I can walk to.
  goal(me) {
    const world = this.world;
    if (world.freeWorkers > 0 && world.open.size > 0) return "open";
    if (me.carry) return "nest";
    if (world.freeWorkers > 0) return null;
    for (const pile of world.piles.values()) if (pile.units > 0 && !pile.far) return "pile";
    return null;
  }

  // The number of steps on foot from each cell to the nearest place of a goal, or -1.
  // `ends` has the place of the goal for each cell where the way ends.
  field(kind) {
    const world = this.world;
    const key = `${world.structure}:${world.pilesKey}`;
    const known = this.fields.get(kind);
    if (known && known.key === key) return known;

    const grid = world.grid;
    const steps = new Int16Array(grid.count).fill(-1);
    const queue = new Int32Array(grid.count);
    const ends = new Map();
    let head = 0;
    let tail = 0;
    // The way to an open cell or to the nest does not go across a pile: a body that
    // touches a pile takes food.
    const piles = new Set();
    if (kind !== "pile") for (const pile of world.piles.values()) if (pile.units > 0) piles.add(pile.cell);
    const start = (cell, end) => {
      if (steps[cell] >= 0 || !world.walkable(cell)) return;
      steps[cell] = 0;
      ends.set(cell, end);
      queue[tail++] = cell;
    };
    if (kind === "nest") {
      start(world.nest, world.nest);
    } else if (kind === "pile") {
      for (const pile of world.piles.values()) if (pile.units > 0 && !pile.far) start(pile.cell, pile.cell);
    } else {
      // A body stands on a cell that touches an open cell.
      for (const open of world.open) for (const cell of grid.neighbors(open)) start(cell, open);
    }
    while (head < tail) {
      const cell = queue[head++];
      // A pile cell gets a number: a body on it has a way out. But no way goes across it.
      if (piles.has(cell)) continue;
      for (let direction = 0; direction < 6; direction++) {
        const next = grid.neighbor(cell, direction);
        if (next < 0 || steps[next] >= 0 || !world.walkable(next)) continue;
        steps[next] = steps[cell] + 1;
        queue[tail++] = next;
      }
    }
    const field = { key, steps, ends, piles };
    this.fields.set(kind, field);
    return field;
  }

  // The way to a goal from a point. Returns { cell, x, z, aimX, aimZ, steps } or null if
  // there is no way. `cell` is the place of the goal. `aim` is the point to walk to now:
  // the farthest point of the way that a straight line gets to.
  route(kind, x, z) {
    const world = this.world;
    const grid = world.grid;
    const field = this.field(kind);
    let cell = grid.cellAt(x, z);
    if (cell < 0 || field.steps[cell] < 0) return null;
    const total = field.steps[cell];
    let aimX = grid.x(cell);
    let aimZ = grid.z(cell);
    let looked = 0;
    let clear = true;
    while (field.steps[cell] > 0) {
      let next = -1;
      for (let direction = 0; direction < 6 && next < 0; direction++) {
        const other = grid.neighbor(cell, direction);
        if (other >= 0 && field.steps[other] === field.steps[cell] - 1) next = other;
      }
      cell = next;
      if (clear && looked < LOOK_STEPS) {
        looked++;
        if (this.clear(x, z, grid.x(cell), grid.z(cell), field.piles)) {
          aimX = grid.x(cell);
          aimZ = grid.z(cell);
        } else {
          clear = false;
        }
      }
    }
    const end = field.ends.get(cell);
    // At the end of the way, the body looks at the place of the goal.
    if (total <= 1 || (clear && looked === total)) {
      aimX = grid.x(end);
      aimZ = grid.z(end);
    }
    return { cell: end, x: grid.x(end), z: grid.z(end), aimX, aimZ, steps: total };
  }

  // True if a body can walk in a straight line from a point to a point. The line does
  // not go across a cell of `avoid`, but it can start on one.
  clear(x0, z0, x1, z1, avoid = null) {
    const world = this.world;
    const grid = world.grid;
    const from = grid.cellAt(x0, z0);
    const distance = Math.hypot(x1 - x0, z1 - z0);
    const parts = Math.ceil(distance / 0.2);
    for (let part = 1; part <= parts; part++) {
      const t = part / parts;
      const x = x0 + (x1 - x0) * t;
      const z = z0 + (z1 - z0) * t;
      if (!world.canStand(x, z)) return false;
      if (avoid && avoid.size > 0) {
        const cell = grid.cellAt(x, z);
        if (cell !== from && avoid.has(cell)) return false;
      }
    }
    return true;
  }

  // The arrow at the edge of the screen, or null. The arrow shows only when its target is
  // not on the screen. `project(x, y, z)` gives the place of a point on the page, in
  // pixels, or null. Returns { goal, x, y, dx, dy }: the place of the arrow on the page
  // and its direction (y is down).
  arrow(me, project, width, height) {
    const goal = me.alive ? this.goal(me) : null;
    const route = goal ? this.route(goal, me.x, me.z) : null;
    if (!route) return null;
    const at = project(route.x, 0, route.z);
    if (at && at[0] >= 0 && at[0] <= width && at[1] >= 0 && at[1] <= height) return null;
    const from = project(me.x, 0, me.z);
    const to = project(route.aimX, 0, route.aimZ);
    if (!from || !to) return null;
    const dx = to[0] - from[0];
    const dy = to[1] - from[1];
    const length = Math.hypot(dx, dy);
    if (length < 1) return null;
    // The arrow is at the edge of the screen, in the direction of the way.
    const margin = 46;
    const top = 64;
    let reach = Infinity;
    if (dx > 0) reach = Math.min(reach, (width - margin - from[0]) / dx);
    if (dx < 0) reach = Math.min(reach, (margin - from[0]) / dx);
    if (dy > 0) reach = Math.min(reach, (height - margin - from[1]) / dy);
    if (dy < 0) reach = Math.min(reach, (top + margin - from[1]) / dy);
    reach = Math.max(0, reach);
    return { goal, x: from[0] + dx * reach, y: from[1] + dy * reach, dx: dx / length, dy: dy / length };
  }

  // What a person sees: the button, the body, the open cells on the screen and the arrow.
  // All the places are in pixels of the page. The script of the new player in the play
  // tests gets only this.
  view(me, ready, arrow, project, width, height) {
    const grid = this.world.grid;
    const open = [];
    for (const cell of this.world.open) {
      const at = project(grid.x(cell), 0, grid.z(cell));
      if (at && at[0] >= 0 && at[0] <= width && at[1] >= 0 && at[1] <= height) open.push(at);
    }
    return { lock: ready, me: project(me.x, 0, me.z), open, arrow: arrow ? [arrow.dx, arrow.dy] : null };
  }
}
