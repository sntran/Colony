// The script of a new player: a person who knows nothing. Plan 0004, section 5.3.
//
// The script knows only what a person sees:
//
// - Each 0.1 seconds: if the button shows the bright lock sign, tap it.
// - If not: push the stick in a straight line to the mark of the guide if it is on the
//   screen. If it is not, push in the direction of the arrow.
// - If the body did not move for 1 second, push to one side for 0.5 seconds, then to the
//   other side.
//
// The slow script is the same, but it waits 6 seconds at the start, 0.5 to 1.1 seconds
// before each tap, and 0.3 to 0.6 seconds after it.
//
// The script does not read the grid, the rivers or the supports.

// A random number generator with a seed: the same seed gives the same waits.
function randomFrom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export class NewPlayer {
  // options: { slow: true, seed }.
  constructor(options = {}) {
    this.slow = Boolean(options.slow);
    this.random = randomFrom(options.seed || 1);
    this.stick = [0, 0];
    this.started = null;
    this.movedAt = 0;
    // While the body is stuck: the time when the push to the side started.
    this.sideAt = null;
    // The slow script: the time to tap, and the time until it does something again.
    this.tapAt = null;
    this.waitUntil = 0;
  }

  // `view` is what a person sees: { lock, me: [x, y], mark: [x, y], arrow: [dx, dy] }.
  // The places are on the screen, in pixels, with y down. `moved` is true if the body
  // moved since the last step. `now` is the time in milliseconds.
  // Returns { tap, stick }: `stick` is [right, up], from -1 to 1.
  step(view, moved, now) {
    if (this.started === null) {
      this.started = now;
      // The slow player looks at the screen for 6 seconds first.
      if (this.slow) this.waitUntil = now + 6000;
    }
    if (moved) this.movedAt = now;
    if (now < this.waitUntil) {
      this.movedAt = now;
      return { tap: false, stick: [0, 0] };
    }

    if (view.lock) {
      // The left thumb stays where it is. The right thumb taps.
      if (!this.slow) return { tap: true, stick: this.stick };
      if (this.tapAt === null) this.tapAt = now + 500 + 600 * this.random();
      if (now < this.tapAt) return { tap: false, stick: this.stick };
      this.tapAt = null;
      this.waitUntil = now + 300 + 300 * this.random();
      return { tap: true, stick: this.stick };
    }
    this.tapAt = null;

    let direction = [0, 0];
    if (view.me && view.mark) {
      const dx = view.mark[0] - view.me[0];
      const dy = view.mark[1] - view.me[1];
      const length = Math.hypot(dx, dy);
      if (length > 0.5) direction = [dx / length, -dy / length];
    } else if (view.arrow) {
      direction = [view.arrow[0], -view.arrow[1]];
    }

    // The body did not move for 1 second: push to one side for 0.5 seconds, then to the
    // other side.
    if (this.sideAt === null && now - this.movedAt >= 1000 && (direction[0] !== 0 || direction[1] !== 0)) {
      this.sideAt = now;
    }
    if (this.sideAt !== null) {
      const time = now - this.sideAt;
      if (time < 500) direction = [-direction[1], direction[0]];
      else if (time < 1000) direction = [direction[1], -direction[0]];
      else {
        this.sideAt = null;
        this.movedAt = now;
      }
    }
    this.stick = direction;
    return { tap: false, stick: direction };
  }
}
