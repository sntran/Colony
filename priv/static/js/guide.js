// What the page tells a player: the guide, the cell for a lock, and the arrow.
//
// The guide is the one target that the page shows at each moment. lib/colony/guide.ex has
// the same rules for the helpers. The first rule that applies gives the target:
//
// 1. I carry food: the nest.
// 2. The colony has a spare body, and an open cell is there: the nearest open cell, by
//    steps on foot.
// 3. A pile with food that I can walk to is there: the nearest such pile.
// 4. Nothing: no target.
//
// Share the work: if the colony has fewer spare bodies than players and helpers, and my
// last act was a lock, rule 3 comes before rule 2. After I bring food, rule 2 comes first
// again.
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
  lockCell(x, z, dx, dz) {
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

  // True if rule 3 comes before rule 2 for me. `last` is my last act: "lock", "carry"
  // or null.
  share(last) {
    return last === "lock" && this.world.spare < this.world.players.size;
  }

  // The guide: { kind, cell, route } or null. `kind` is "nest", "open" or "pile". `cell`
  // is the place of the target. `route` is the way to it: see `route`.
  guide(me, last) {
    if (!me.alive) return null;
    if (me.carry) return this.target("nest", me);
    const rules = this.share(last) ? ["pile", "open"] : ["open", "pile"];
    for (const kind of rules) {
      if (kind === "open" && (this.world.spare === 0 || this.world.open.size === 0)) continue;
      const target = this.target(kind, me);
      if (target) return target;
    }
    return null;
  }

  target(kind, me) {
    const route = kind === "open" ? this.openRoute(me.x, me.z) : this.route(kind, me.x, me.z);
    return route ? { kind, cell: route.cell, route } : null;
  }

  // The way to the nearest open cell, by steps on foot. Of the open cells with the same
  // number of steps, the cell nearest in a straight line. Returns a route as `route`.
  openRoute(x, z) {
    const world = this.world;
    const grid = world.grid;
    const here = grid.cellAt(x, z);
    if (here < 0 || world.open.size === 0) return null;
    const key = `${world.structure}:${world.pilesKey}:${here}`;
    if (this.openCache && this.openCache.key === key) return this.openCache.route;

    // The way does not go across a pile: a body that touches a pile takes food.
    const piles = new Set();
    for (const pile of world.piles.values()) if (pile.units > 0) piles.add(pile.cell);
    const before = new Map([[here, -1]]);
    let front = [here];
    let found = null;
    while (front.length > 0 && !found) {
      let least = Infinity;
      for (const cell of front) {
        for (const open of grid.neighbors(cell)) {
          if (!world.open.has(open)) continue;
          // Of the open cells with the same number of steps: the cell nearest in a
          // straight line, then the lowest cell number. The server does the same.
          const distance = Math.hypot(grid.x(open) - x, grid.z(open) - z);
          if (distance < least - 1e-9 || (Math.abs(distance - least) <= 1e-9 && open < found.open)) {
            least = distance;
            found = { open, stand: cell };
          }
        }
      }
      if (found) break;
      const next = [];
      for (const cell of front) {
        if (cell !== here && piles.has(cell)) continue;
        for (const to of grid.neighbors(cell)) {
          if (before.has(to) || !world.walkable(to)) continue;
          before.set(to, cell);
          next.push(to);
        }
      }
      front = next;
    }

    let route = null;
    if (found) {
      const path = [];
      for (let cell = found.stand; cell !== here; cell = before.get(cell)) path.unshift(cell);
      route = this.along(x, z, path, found.open);
    }
    this.openCache = { key, route };
    return route;
  }

  // A route along the cells of a path to a target cell: { cell, x, z, aimX, aimZ, steps }.
  // `aim` is the point to walk to now: the farthest point of the path that a straight
  // line gets to.
  along(x, z, path, target) {
    const grid = this.world.grid;
    let aimX = path.length > 0 ? grid.x(path[0]) : grid.x(target);
    let aimZ = path.length > 0 ? grid.z(path[0]) : grid.z(target);
    for (let i = 0; i < Math.min(path.length, LOOK_STEPS); i++) {
      if (!this.clear(x, z, grid.x(path[i]), grid.z(path[i]))) break;
      aimX = grid.x(path[i]);
      aimZ = grid.z(path[i]);
    }
    // At the end of the way, the body looks at the target.
    if (path.length <= 1) {
      aimX = grid.x(target);
      aimZ = grid.z(target);
    }
    return { cell: target, x: grid.x(target), z: grid.z(target), aimX, aimZ, steps: path.length };
  }

  // The number of steps on foot from each cell to the nearest place of a goal, or -1.
  // `ends` has the place of the goal for each cell where the way ends.
  field(kind) {
    const world = this.world;
    const key = `${world.structure}:${world.pilesKey}:${world.nest}`;
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
      for (const open of world.open.keys()) for (const cell of grid.neighbors(open)) start(cell, open);
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

  // The arrow at the edge of the screen, or null. The arrow shows only when the target of
  // the guide is not on the screen. `project(x, y, z)` gives the place of a point on the
  // page, in pixels, or null. Returns { goal, x, y, dx, dy }: the place of the arrow on
  // the page and its direction (y is down).
  arrow(me, guide, project, width, height) {
    if (!guide) return null;
    const route = guide.route;
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
    return { goal: guide.kind, x: from[0] + dx * reach, y: from[1] + dy * reach, dx: dx / length, dy: dy / length };
  }

  // What a person sees: the button, the body, the mark of the guide and the arrow. All the
  // places are in pixels of the page. The script of the new player in the play tests gets
  // only this. `button` is the state of the button: see main.js.
  view(me, button, guide, arrow, project, width, height) {
    const grid = this.world.grid;
    let mark = null;
    if (guide) {
      const at = project(grid.x(guide.cell), 0, grid.z(guide.cell));
      if (at && at[0] >= 0 && at[0] <= width && at[1] >= 0 && at[1] <= height) mark = at;
    }
    return { lock: button === "lock", button, me: project(me.x, 0, me.z), mark, arrow: arrow ? [arrow.dx, arrow.dy] : null };
  }
}
