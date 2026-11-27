// The script of a new player: a person who knows nothing. Plan 0003, section 5.3.
//
// The script knows only what a person sees:
//
// - Each 0.1 seconds: if the button Lock is bright, tap it.
// - If not: push the stick in a straight line to the nearest open cell on the screen. If
//   no open cell is on the screen, push in the direction of the arrow.
// - If the body did not move for 1 second, push to one side for 0.5 seconds, then to the
//   other side.
//
// The script does not read the grid, the rivers or the supports.

export class NewPlayer {
  constructor() {
    this.stick = [0, 0];
    this.started = false;
    this.movedAt = 0;
    // While the body is stuck: the time when the push to the side started.
    this.sideAt = null;
  }

  // `view` is what a person sees: { lock, me: [x, y], open: [[x, y], ...], arrow: [dx, dy] }.
  // The places are on the screen, in pixels, with y down. `moved` is true if the body
  // moved since the last step. `now` is the time in milliseconds.
  // Returns { tap, stick }: `stick` is [right, up], from -1 to 1.
  step(view, moved, now) {
    if (moved || !this.started) this.movedAt = now;
    this.started = true;

    if (view.lock) {
      // The left thumb stays where it is. The right thumb taps.
      return { tap: true, stick: this.stick };
    }

    let direction = [0, 0];
    if (view.me && view.open.length > 0) {
      let best = null;
      let least = Infinity;
      for (const at of view.open) {
        const distance = Math.hypot(at[0] - view.me[0], at[1] - view.me[1]);
        if (distance < least) {
          least = distance;
          best = at;
        }
      }
      const length = Math.hypot(best[0] - view.me[0], best[1] - view.me[1]) || 1;
      direction = [(best[0] - view.me[0]) / length, -(best[1] - view.me[1]) / length];
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
