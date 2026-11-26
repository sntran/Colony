// The support rule. This file has the same rule as lib/colony/support.ex.
//
// The page uses it to show where a lock is possible and how far a bridge can go. The
// server decides: it does the same calculation when a player locks.
//
// All the numbers are integers. The bank support is 96 and the costs are 12, 6, 4 and 3:
// the cost of a body is 12 divided by the number of bodies in its line, 4 at most.

import { GAP } from "./hex.js";

// The number of bodies in the line that contains the cell. `has(cell)` tells if a body is
// in a cell. A body is in the cell, or will be.
export function line(grid, has, cell) {
  const row = grid.row(cell);
  let count = 1;
  for (let next = cell - 1; next >= 0 && grid.row(next) === row && has(next); next--) count++;
  for (let next = cell + 1; grid.row(next) === row && has(next); next++) count++;
  return count;
}

export function cost(grid, rule, has, cell) {
  return rule.costs[Math.min(line(grid, has, cell), rule.costs.length) - 1];
}

// The cells with a body that touch each other, from one cell.
export function group(grid, has, cell) {
  const seen = new Set([cell]);
  const cells = [cell];
  for (let i = 0; i < cells.length; i++) {
    for (const next of grid.neighbors(cells[i])) {
      if (!seen.has(next) && has(next)) {
        seen.add(next);
        cells.push(next);
      }
    }
  }
  return cells;
}

// The support of each cell of `cells`: a Map from cell to support. A cell that no bank
// can reach is not in the result.
export function calculate(grid, rule, cells, has) {
  const costs = new Map();
  const best = new Map();
  for (const cell of cells) {
    const value = cost(grid, rule, has, cell);
    costs.set(cell, value);
    if (grid.touchesBank(cell)) best.set(cell, rule.bank - value);
  }
  const done = new Map();
  // The cell with the highest support is first. Thus the first value of a cell is its
  // highest value.
  while (best.size > 0) {
    let cell = -1;
    let support = -Infinity;
    for (const [candidate, value] of best) {
      if (value > support) {
        support = value;
        cell = candidate;
      }
    }
    best.delete(cell);
    done.set(cell, support);
    for (const next of grid.neighbors(cell)) {
      if (!costs.has(next) || done.has(next)) continue;
      const value = support - costs.get(next);
      if (!best.has(next) || best.get(next) < value) best.set(next, value);
    }
  }
  return done;
}

// The supports of a bridge if a body locks into an empty river cell: for the new cell
// and for all the bodies that touch it, directly or through other bodies.
export function withBody(grid, rule, locked, cell) {
  const has = (other) => other === cell || locked.has(other);
  return calculate(grid, rule, group(grid, has, cell), has);
}

// True if a body can lock into the cell.
export function canLock(grid, rule, locked, cell) {
  if (cell < 0 || grid.kind(cell) !== GAP || locked.has(cell)) return false;
  return (withBody(grid, rule, locked, cell).get(cell) || 0) > 0;
}

// The reach of a bridge if a body locks into `cell`: how far the bridge can then grow,
// one body wide, in a straight line to the far bank.
//
// Returns { cells, bank, part, next }:
//   cells: one cell in each row that the bridge can get to after the lock
//   bank: the cell of the far bank that the bridge gets to, or -1
//   next: the cell of the first row that the bridge cannot get to, or -1
//   part: how near the bridge is to that row, from 0 to 1
export function reach(grid, rule, locked, cell) {
  const supports = withBody(grid, rule, locked, cell);
  const taken = (other) => other === cell || locked.has(other);
  let best = null;

  for (const [from, support] of supports) {
    if (support <= 0) continue;
    const cells = [];
    const added = new Set();
    const has = (other) => taken(other) || added.has(other);
    let at = from;
    let left = support;
    let bank = -1;
    let next = -1;
    let part = 0;
    for (;;) {
      const to = grid.straight(at);
      if (to < 0) break;
      if (grid.kind(to) !== GAP) {
        bank = to;
        break;
      }
      // A body is in the next row already: this body is not the end of the bridge.
      if (taken(to)) {
        if (cells.length === 0) next = -2;
        break;
      }
      added.add(to);
      const price = cost(grid, rule, has, to);
      if (left - price > 0) {
        cells.push(to);
        left -= price;
        at = to;
      } else {
        added.delete(to);
        next = to;
        part = Math.max(0, Math.min(1, (left - 1) / price));
        break;
      }
    }
    if (next === -2) continue;
    const row = grid.riverRow(at);
    const score = (bank >= 0 ? 1000 : 0) + row + part * 0.9 + (from === cell ? 0.01 : 0);
    if (!best || score > best.score) best = { cells, bank, next, part, score, row };
  }
  return best || { cells: [], bank: -1, next: -1, part: 0, score: 0, row: 0 };
}
