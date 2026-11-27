// The grid of hexagonal cells. It is the same grid as in lib/colony/grid.ex.
//
// A cell is an integer: row * width + column. The rows go from the south to the north.
// The rows with an odd number are half a cell to the right. The world is land 0, river 1,
// land 1, river 2, and so on.

export const ROW_STEP = Math.sqrt(3) / 2;

export const LAND = 0;
export const GAP = 1;

export class Grid {
  // `rivers` is a list of { start, widths }: the first row of a river and its width in
  // each column.
  constructor(width, rows, rivers) {
    this.width = width;
    this.rows = rows;
    this.rivers = rivers;
    this.count = width * rows;
    // For each cell: 0 for land, or the number of its river. And the number of its land.
    this.rivered = new Uint8Array(this.count);
    this.lands = new Uint8Array(this.count);
    for (let cell = 0; cell < this.count; cell++) {
      const row = Math.floor(cell / width);
      const [river, land] = this.zone(row, cell % width);
      this.rivered[cell] = river;
      this.lands[cell] = land;
    }
  }

  // [river, land] of a row and a column. Outside of the grid, a river continues with the
  // width of its first or its last column.
  zone(row, col) {
    const c = Math.max(0, Math.min(this.width - 1, col));
    let land = 0;
    for (let k = 0; k < this.rivers.length; k++) {
      const river = this.rivers[k];
      if (row < river.start) break;
      if (row < river.start + river.widths[c]) return [k + 1, k + 1];
      land = k + 1;
    }
    return [0, land];
  }

  row(cell) {
    return Math.floor(cell / this.width);
  }

  col(cell) {
    return cell % this.width;
  }

  kind(cell) {
    return this.rivered[cell] === 0 ? LAND : GAP;
  }

  // The number of the river of a river cell, from 1. For a land cell: 0.
  river(cell) {
    return this.rivered[cell];
  }

  // The number of the land of a land cell, from 0.
  land(cell) {
    return this.lands[cell];
  }

  // The row of a river cell in its river, from 1 at the south edge.
  riverRow(cell) {
    return Math.floor(cell / this.width) - this.rivers[this.rivered[cell] - 1].start + 1;
  }

  x(cell) {
    const row = Math.floor(cell / this.width);
    return (cell % this.width) + 0.5 * (row & 1);
  }

  z(cell) {
    return Math.floor(cell / this.width) * ROW_STEP;
  }

  // The cell that contains a point, or -1.
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
