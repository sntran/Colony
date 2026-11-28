// The story of the colony: all the locked bodies appear in the order of their times, from
// the nest to the north. At the end, the page shows the full world from above, with the
// names. A button saves that picture. The picture of a long world is taller: the page
// draws it in parts, from the north to the south.

import { ROW_STEP } from "./hex.js";
import { colorOf, cssColor, HELPER_COLOR } from "./names.js";

// The story takes 0.25 seconds for each body: 6 seconds at the least and 40 at the most.
const LEAST_SECONDS = 6;
const MOST_SECONDS = 40;
const SECONDS_EACH_LOCK = 0.25;
// A long picture has about this many pixels in its length, but not less than one canvas
// pixel for each page pixel.
const PICTURE_MOST = 6000;
// The camera goes from the play view to the view from above in this many seconds.
const TURN_SECONDS = 2.2;
const NAME_SECONDS = 2.6;

const mix = (a, b, t) => a + (b - a) * t;
const smooth = (t) => t * t * (3 - 2 * t);

export class Story {
  // parts: { world, renderer, sound, net, canvas }.
  constructor(parts) {
    Object.assign(this, parts);
    // "off", "play" (the bodies appear), or "end" (the world from above).
    this.phase = "off";
    this.time = 0;
    this.shown = 0;
    this.locks = [];
    this.names = [];
    this.labels = [];
    this.info = null;
    this.onChange = () => {};
    // How many times the story played to its end. A test reads it.
    this.plays = 0;
    // The order of the bodies that appeared in the last play. A test reads it.
    this.order = [];
  }

  get running() {
    return this.phase !== "off";
  }

  // All the locks in the order of their times, and the players. The page has the locks:
  // the server sends each one. The server gives the food of each player.
  data() {
    const locks = [...this.world.locked.values()]
      .sort((a, b) => a.n - b.n)
      .map((body) => ({ n: body.n, cell: body.cell, name: body.name, helper: body.helper, river: body.river, row: body.row }));
    return { locks, names: this.names };
  }

  // The players with their bodies, their food and the walks on their bodies. The bodies
  // come from the locks that the page has. The food and the walks come from the server.
  count(info) {
    const players = new Map();
    const key = (name, helper) => `${helper ? 1 : 0}:${name}`;
    for (const body of this.world.locked.values()) {
      const id = key(body.name, body.helper);
      if (!players.has(id)) players.set(id, { name: body.name, helper: body.helper, bodies: 0, food: 0 });
      players.get(id).bodies++;
    }
    for (const entry of info && info.names ? info.names : []) {
      const id = key(entry.name, entry.helper);
      if (!players.has(id)) players.set(id, { name: entry.name, helper: entry.helper, bodies: 0, food: 0 });
      players.get(id).food = entry.food;
      // The walks on the bodies of the player: the server counts them.
      players.get(id).walks = entry.walks || 0;
    }
    return [...players.values()].sort((a, b) => b.bodies - a.bodies || b.food - a.food || (a.name < b.name ? -1 : 1));
  }

  // Starts the story. It works at each time, also before the world is complete.
  async open() {
    if (this.running || !this.world.ready) return;
    this.phase = "play";
    this.time = 0;
    this.shown = 0;
    this.order = [];
    this.labels = [];
    this.locks = [...this.world.locked.values()].sort((a, b) => a.n - b.n);
    this.seconds = Math.max(LEAST_SECONDS, Math.min(MOST_SECONDS, this.locks.length * SECONDS_EACH_LOCK));
    this.named = new Set();
    this.world.storyLimit = 0;
    this.world.hideFree = true;
    this.names = this.count(null);
    this.onChange();
    this.info = await this.net.story();
    this.names = this.count(this.info);
    this.onChange();
  }

  // Goes to the end of the story immediately: the world from above.
  skip() {
    if (this.phase !== "play") return;
    this.time = this.seconds + 1;
  }

  close() {
    if (!this.running) return;
    this.phase = "off";
    this.world.storyLimit = Infinity;
    this.world.hideFree = false;
    this.labels = [];
    this.onChange();
  }

  // The time when the body number `index` appears.
  at(index) {
    const count = this.locks.length;
    return 1 + ((this.seconds - 2.5) * index) / Math.max(1, count - 1);
  }

  // Moves the story. `camera` is the camera of the page: the story sets it.
  update(dt, camera) {
    if (!this.running) return;
    const world = this.world;
    const grid = world.grid;
    this.time += dt;

    if (this.phase === "play") {
      while (this.shown < this.locks.length && this.time >= this.at(this.shown)) {
        const body = this.locks[this.shown++];
        // The body goes down into its cell, as at its lock, and its note plays.
        body.start = world.time;
        body.from = null;
        world.storyLimit = body.n;
        this.order.push(body.n);
        this.sound.lock(body.river, body.row, 0.7, "story");
        this.wave(body);
        // The first body of each player shows the name.
        const id = `${body.helper ? 1 : 0}:${body.name}`;
        if (!this.named.has(id)) {
          this.named.add(id);
          this.labels.push({ name: body.name, helper: body.helper, x: body.x, z: body.z, until: this.time + NAME_SECONDS });
        }
      }
      this.labels = this.labels.filter((label) => label.until > this.time);

      // The camera goes from the nest to the north, with the bodies.
      const last = this.shown > 0 ? this.locks[this.shown - 1] : null;
      const next = this.shown < this.locks.length ? this.locks[this.shown] : last;
      const x = next ? next.x : grid.x(world.nest);
      const z = next ? next.z : grid.z(world.nest);
      const follow = 1 - Math.exp(-dt * 1.6);
      if (this.time < 0.05) {
        camera.x = grid.x(world.nest);
        camera.z = grid.z(world.nest);
      }
      camera.x += (x - camera.x) * follow;
      camera.z += (z + 1 - camera.z) * follow;
      const tall = this.canvas.clientWidth < this.canvas.clientHeight ? 1.25 : 1;
      camera.turn = 0.18 * Math.sin(this.time * 0.25);
      camera.height = 12 * tall;
      camera.distance = 9 * tall;
      camera.fov = (52 * Math.PI) / 180;
      camera.far = 140;
      if (this.time >= this.seconds) {
        this.phase = "end";
        this.endTime = this.time;
        this.from = { ...camera };
        world.storyLimit = Infinity;
        world.hideFree = false;
        this.labels = [];
        this.plays++;
        this.onChange();
      }
    } else {
      // The full world from above. The north is up.
      const to = this.above();
      const part = smooth(Math.min(1, (this.time - this.endTime) / TURN_SECONDS));
      for (const name of ["x", "z", "turn", "height", "distance", "fov"]) camera[name] = mix(this.from[name], to[name], part);
      camera.far = to.far;
    }
  }

  // A ring on the water where a body appears. The page gives this function.
  wave() {}

  // The camera that shows the full world from above. On a tall screen, the world is at
  // the top, above the list of the names: the list can cover 38 percent of the screen.
  above() {
    const grid = this.world.grid;
    const width = grid.width + 3;
    const north = (grid.rows - 1) * ROW_STEP + 2.5;
    const south = -2.5;
    const aspect = this.canvas.clientWidth / this.canvas.clientHeight;
    const fov = (26 * Math.PI) / 180;
    const tan = Math.tan(fov / 2);
    // The world must be in the picture in its length and in its width.
    const height = Math.max((north - south) / 2 / tan / 0.54, width / 2 / (tan * aspect) / 0.98);
    // The distance in the world for the height of the screen, and for the buttons at the top.
    const seen = 2 * height * tan;
    const top = (64 / this.canvas.clientHeight) * seen;
    const z = Math.min((north + south) / 2, north + top - seen / 2);
    return { x: (grid.width - 0.5) / 2, z, turn: 0, height, distance: 0.01, fov, far: Math.max(600, height * 1.3 + 50) };
  }

  // The cameras for the picture of the world, from the north to the south. Each camera
  // looks down at one part of the world with the full width of the world on the screen.
  // A short world has one part. Returns { cameras, length, north, south }: `length` is the
  // part of the world along its length in each picture of the screen.
  parts() {
    const grid = this.world.grid;
    const width = grid.width + 3;
    const north = (grid.rows - 1) * ROW_STEP + 2.5;
    const south = -2.5;
    const aspect = this.canvas.clientWidth / this.canvas.clientHeight;
    const fov = (26 * Math.PI) / 180;
    const tan = Math.tan(fov / 2);
    const height = width / 2 / (tan * aspect) / 0.98;
    const length = 2 * height * tan;
    const count = Math.ceil((north - south) / length);
    const far = height * 1.3 + 50;
    // A short world: one camera at the middle of the world.
    if (count <= 1) return { cameras: [{ x: (grid.width - 0.5) / 2, z: (north + south) / 2, turn: 0, height, distance: 0.01, fov, far }], length, north, south };
    const cameras = [];
    for (let i = 0; i < count; i++) {
      cameras.push({ x: (grid.width - 0.5) / 2, z: north - length * (i + 0.5), turn: 0, height, distance: 0.01, fov, far });
    }
    return { cameras, length, north, south };
  }

  // The part of the canvas that has the world, in canvas pixels: [x, y, width, height].
  frame() {
    const grid = this.world.grid;
    const scale = this.canvas.width / this.canvas.clientWidth;
    const a = this.renderer.project(grid.width + 1, 0, (grid.rows - 1) * ROW_STEP + 2.5);
    const b = this.renderer.project(-1.5, 0, -2.5);
    if (!a || !b) return [0, 0, this.canvas.width, this.canvas.height];
    const x = Math.max(0, Math.round(Math.min(a[0], b[0]) * scale));
    const y = Math.max(0, Math.round(Math.min(a[1], b[1]) * scale));
    const right = Math.min(this.canvas.width, Math.round(Math.max(a[0], b[0]) * scale));
    const bottom = Math.min(this.canvas.height, Math.round(Math.max(a[1], b[1]) * scale));
    return [x, y, right - x, bottom - y];
  }

  // What the story does now. A test reads it.
  state() {
    return { phase: this.phase, shown: this.shown, total: this.locks.length, seconds: this.seconds, time: this.time, plays: this.plays };
  }

  // -------------------------------------------------------------------------
  // The picture

  // Makes the picture of the world from above as a PNG file: a promise of a Blob. The
  // picture has the date and the names. `draw(camera, scale)` draws the world on the
  // canvas now, with the camera and the number of canvas pixels for each page pixel.
  picture(draw) {
    const source = this.canvas;
    const { cameras, length, north, south } = this.parts();
    let image;
    let width;
    let height;
    if (cameras.length === 1) {
      draw(cameras[0], 2);
      // Only the part of the canvas that has the world goes into the picture.
      const [left0, top0, w, h] = this.frame();
      width = w;
      height = h;
      image = (g) => g.drawImage(source, left0, top0, width, height, 0, 0, width, height);
      image.parts = null;
    } else {
      // A long world: one picture of the screen for each part, one below the other. The
      // number of pixels is less for a very long world.
      const scale = Math.max(1, Math.min(2, PICTURE_MOST / (cameras.length * source.clientHeight)));
      const parts = document.createElement("canvas");
      let partHeight = 0;
      cameras.forEach((camera, index) => {
        draw(camera, scale);
        if (index === 0) {
          width = source.width;
          partHeight = source.height;
          height = Math.round(((north - south) / length) * partHeight);
          parts.width = width;
          parts.height = height;
        }
        // The canvas has the picture only in the task that drew it.
        parts.getContext("2d").drawImage(source, 0, index * partHeight);
      });
      image = (g) => g.drawImage(parts, 0, 0);
    }
    this.pictureParts = cameras.length;
    const unit = width / 390;
    const names = this.names;
    // Each name shows fully, with its numbers: one column when a name or its numbers are
    // too long for two columns.
    const measure = document.createElement("canvas").getContext("2d");
    const font = (size, weight = 600) => `${weight} ${Math.round(size * unit)}px system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`;
    measure.font = font(13, 500);
    const numbers = (entry) => measure.measureText(`${entry.bodies}${entry.food}`).width + 36 * unit;
    const fits = (entry) => measure.measureText(entry.name).width <= 108 * unit && numbers(entry) <= 56 * unit;
    const columns = names.every(fits) ? 2 : 1;
    const rows = Math.ceil(names.length / columns);
    const band = Math.round((54 + rows * 24) * unit);
    const out = document.createElement("canvas");
    out.width = width;
    out.height = height + band;
    const g = out.getContext("2d");
    g.fillStyle = "#16201c";
    g.fillRect(0, 0, out.width, out.height);
    image(g);

    // The name of the game and the date, on the picture.
    const start = new Date((this.info && this.info.start ? this.info.start : this.world.startTime) * 1000);
    g.textBaseline = "middle";
    g.shadowColor = "rgba(0, 0, 0, 0.65)";
    g.shadowBlur = 6 * unit;
    g.fillStyle = "#fff";
    g.font = font(24, 700);
    g.fillText("Colony", 16 * unit, 26 * unit);
    g.font = font(14, 500);
    g.textAlign = "right";
    this.pictureDate = start.toLocaleDateString();
    g.fillText(this.pictureDate, width - 16 * unit, 26 * unit);
    g.textAlign = "left";
    g.shadowBlur = 0;

    // The numbers of the world, then the names with their bodies and their food.
    const top = height + 24 * unit;
    g.font = font(15, 700);
    g.fillStyle = "#fff";
    const crossings = this.info ? this.info.crossings : this.world.stage - 1;
    let x = 16 * unit;
    x = this.sign(g, "river", x, top, unit) + 4 * unit;
    x = this.text(g, `${crossings}`, x, top) + 16 * unit;
    x = this.sign(g, "body", x, top, unit) + 4 * unit;
    x = this.text(g, `${this.world.locked.size}`, x, top) + 16 * unit;
    x = this.sign(g, "food", x, top, unit) + 4 * unit;
    this.text(g, `${this.world.foodNest}`, x, top);

    this.pictureNames = [];
    g.font = font(13, 500);
    names.forEach((entry, index) => {
      const column = index % columns;
      const y = height + (54 + Math.floor(index / columns) * 24) * unit;
      const left = (16 + column * 187) * unit;
      g.fillStyle = cssColor(entry.helper ? HELPER_COLOR : colorOf(entry.name));
      g.beginPath();
      g.arc(left + 5 * unit, y, 5 * unit, 0, 6.3);
      g.fill();
      g.fillStyle = entry.helper ? "#b9c0c4" : "#fff";
      g.fillText(entry.name, left + 15 * unit, y);
      // The numbers are after the longest name of the column.
      let at = left + (columns === 2 ? 127 : 15 + Math.max(...names.map((other) => g.measureText(other.name).width / unit)) + 12) * unit;
      at = this.text(g, `${entry.bodies}`, at, y) + 2 * unit;
      at = this.sign(g, "body", at, y, unit * 0.8) + 8 * unit;
      at = this.text(g, `${entry.food}`, at, y) + 2 * unit;
      this.sign(g, "food", at, y, unit * 0.8);
      this.pictureNames.push(entry.name);
    });
    return new Promise((resolve) => out.toBlob(resolve, "image/png"));
  }

  text(g, text, x, y) {
    g.fillText(text, x, y);
    return x + g.measureText(text).width;
  }

  // A small sign in the picture. Returns the x position after it.
  sign(g, name, x, y, unit) {
    const s = 16 * unit;
    g.save();
    g.translate(x, y - s / 2);
    g.scale(s / 24, s / 24);
    if (name === "food") {
      for (const [cx, cy, r, color] of [[8, 15, 5, "#ffbd33"], [16, 15.5, 4.4, "#ffc94d"], [12.5, 8.5, 4.6, "#ffd76a"]]) {
        g.fillStyle = color;
        g.beginPath();
        g.arc(cx, cy, r, 0, 6.3);
        g.fill();
      }
    } else if (name === "body") {
      g.fillStyle = "#fff";
      for (const [cy, rx, ry] of [[5.2, 2.6, 2.4], [11, 2.2, 2.6], [18, 3.6, 4.4]]) {
        g.beginPath();
        g.ellipse(12, cy, rx, ry, 0, 0, 6.3);
        g.fill();
      }
      g.strokeStyle = "#fff";
      g.lineWidth = 1.6;
      g.stroke(new Path2D("M10 9.5 5 7M14 9.5l5-2.5M9.8 11H4.5M14.2 11h5.3M10 12.6 5.5 16M14 12.6l4.5 3.4"));
    } else {
      g.strokeStyle = "#fff";
      g.lineWidth = 2;
      g.lineCap = "round";
      g.stroke(new Path2D("M2 8c3-3 5 3 8 0s5 3 8 0 3 1 4 0M2 15c3-3 5 3 8 0s5 3 8 0 3 1 4 0"));
    }
    g.restore();
    return x + s;
  }

  // Saves the picture: the share function of the phone if the browser has it, or a file.
  // Returns "share", "file" or "none".
  async save(draw) {
    const blob = await this.picture(draw);
    if (!blob) return "none";
    this.pictureSize = blob.size;
    const name = `colony-${new Date().toISOString().slice(0, 10)}.png`;
    const file = typeof File === "function" ? new File([blob], name, { type: "image/png" }) : null;
    if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
      try {
        await navigator.share({ files: [file], title: "Colony" });
        return "share";
      } catch (_) {
        // The person closed the share function, or the browser refused it: save a file.
      }
    }
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(link.href), 10000);
    return "file";
  }
}
