// The grid of hexagonal cells. This file has the same math as lib/colony/grid.ex.
//
// A cell is an integer: row * width + column. The rows with an odd number are moved half a
// cell to the right. The distance between the centers of two cells that touch is 1.

export const ROW_STEP = Math.sqrt(3) / 2;

export const NEAR = 0;
export const GAP = 1;
export const FAR = 2;

export class Grid {
  constructor(width, nearRows, gapRows, farRows) {
    this.width = width;
    this.nearRows = nearRows;
    this.gapRows = gapRows;
    this.farRows = farRows;
    this.rows = nearRows + gapRows + farRows;
    this.count = width * this.rows;
  }

  row(cell) {
    return Math.floor(cell / this.width);
  }

  col(cell) {
    return cell % this.width;
  }

  kind(cell) {
    const row = Math.floor(cell / this.width);
    if (row < this.nearRows) return NEAR;
    if (row < this.nearRows + this.gapRows) return GAP;
    return FAR;
  }

  x(cell) {
    const row = Math.floor(cell / this.width);
    return (cell % this.width) + 0.5 * (row & 1);
  }

  z(cell) {
    return Math.floor(cell / this.width) * ROW_STEP;
  }

  // The cell that contains the point, or -1 if the point is not on the grid.
  cellAt(x, z) {
    const r = z / ROW_STEP;
    const q = x - r / 2;
    const s = -q - r;
    let rq = Math.round(q);
    let rr = Math.round(r);
    const rs = Math.round(s);
    const dq = Math.abs(rq - q);
    const dr = Math.abs(rr - r);
    const ds = Math.abs(rs - s);
    if (dq > dr && dq > ds) rq = -rr - rs;
    else if (dr > ds) rr = -rq - rs;
    const col = rq + (rr - (rr & 1)) / 2;
    if (rr < 0 || rr >= this.rows || col < 0 || col >= this.width) return -1;
    return rr * this.width + col;
  }

  // The cell in a direction, or -1. The directions: 0 right, 1 left, 2 next row right,
  // 3 next row left, 4 row before right, 5 row before left.
  neighbor(cell, direction) {
    let row = Math.floor(cell / this.width);
    let col = cell % this.width;
    const shift = row & 1;
    switch (direction) {
      case 0: col += 1; break;
      case 1: col -= 1; break;
      case 2: row += 1; col += shift; break;
      case 3: row += 1; col += shift - 1; break;
      case 4: row -= 1; col += shift; break;
      default: row -= 1; col += shift - 1;
    }
    if (row < 0 || row >= this.rows || col < 0 || col >= this.width) return -1;
    return row * this.width + col;
  }

  neighbors(cell) {
    const list = [];
    for (let direction = 0; direction < 6; direction++) {
      const next = this.neighbor(cell, direction);
      if (next >= 0) list.push(next);
    }
    return list;
  }
}
