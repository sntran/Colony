// Input from keys and from touch.
//
// Keys: the arrow keys or W, A, S, D move the body. Space locks. Shift puts scent.
// Touch: a stick below the left thumb moves the body. Two buttons: Lock and Scent.

const STICK_RADIUS = 46;
const DEAD_ZONE = 0.14;

export class Input {
  // elements: { zone, stick, knob, lock, scent, canvas }
  // handlers: { lock(), tap(x, y) }
  constructor(elements, handlers) {
    this.elements = elements;
    this.handlers = handlers;
    // The direction on the screen: x is to the right, y is up. The length is 0 to 1.
    this.x = 0;
    this.y = 0;

    this.keys = new Set();
    this.stick = { id: null, x: 0, y: 0, baseX: 0, baseY: 0 };

    this.listenKeys();
    this.listenStick();
    this.listenButtons();
    this.listenTaps();
  }

  listenKeys() {
    const moves = {
      ArrowUp: "up", KeyW: "up", ArrowDown: "down", KeyS: "down",
      ArrowLeft: "left", KeyA: "left", ArrowRight: "right", KeyD: "right",
    };
    window.addEventListener("keydown", (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      if (moves[event.code]) {
        this.keys.add(moves[event.code]);
        event.preventDefault();
      } else if (event.code === "Space") {
        if (!event.repeat) this.handlers.lock();
        event.preventDefault();
      }
      this.refresh();
    });
    window.addEventListener("keyup", (event) => {
      if (moves[event.code]) this.keys.delete(moves[event.code]);
      this.refresh();
    });
    window.addEventListener("blur", () => {
      this.keys.clear();
      this.releaseStick();
      this.refresh();
    });
  }

  listenStick() {
    const { zone, stick } = this.elements;
    zone.addEventListener("pointerdown", (event) => {
      if (this.stick.id !== null) return;
      zone.setPointerCapture(event.pointerId);
      // The stick moves to the place of the thumb.
      const box = zone.getBoundingClientRect();
      this.stick.id = event.pointerId;
      this.stick.baseX = event.clientX;
      this.stick.baseY = event.clientY;
      stick.style.left = `${event.clientX - box.left}px`;
      stick.style.top = `${event.clientY - box.top}px`;
      stick.classList.add("held");
      this.moveStick(event);
      event.preventDefault();
    });
    zone.addEventListener("pointermove", (event) => {
      if (event.pointerId === this.stick.id) this.moveStick(event);
    });
    const end = (event) => {
      if (event.pointerId === this.stick.id) this.releaseStick();
    };
    zone.addEventListener("pointerup", end);
    zone.addEventListener("pointercancel", end);
  }

  moveStick(event) {
    let dx = (event.clientX - this.stick.baseX) / STICK_RADIUS;
    let dy = (event.clientY - this.stick.baseY) / STICK_RADIUS;
    const length = Math.hypot(dx, dy);
    if (length > 1) {
      dx /= length;
      dy /= length;
    }
    this.stick.x = dx;
    this.stick.y = -dy;
    this.elements.knob.style.transform = `translate(${dx * STICK_RADIUS}px, ${dy * STICK_RADIUS}px)`;
    this.refresh();
  }

  releaseStick() {
    this.stick.id = null;
    this.stick.x = 0;
    this.stick.y = 0;
    this.elements.knob.style.transform = "";
    this.elements.stick.classList.remove("held");
    this.elements.stick.style.left = "";
    this.elements.stick.style.top = "";
    this.refresh();
  }

  listenButtons() {
    const { lock } = this.elements;
    lock.addEventListener("pointerdown", (event) => {
      this.handlers.lock();
      event.preventDefault();
    });
    for (const element of [lock, this.elements.zone]) {
      element.addEventListener("contextmenu", (event) => event.preventDefault());
    }
  }

  listenTaps() {
    const { canvas } = this.elements;
    let start = null;
    canvas.addEventListener("pointerdown", (event) => {
      start = { x: event.clientX, y: event.clientY, time: performance.now() };
    });
    canvas.addEventListener("pointerup", (event) => {
      if (start && performance.now() - start.time < 400 && Math.hypot(event.clientX - start.x, event.clientY - start.y) < 12) {
        this.handlers.tap(event.clientX, event.clientY);
      }
      start = null;
    });
  }

  refresh() {
    let x = (this.keys.has("right") ? 1 : 0) - (this.keys.has("left") ? 1 : 0);
    let y = (this.keys.has("up") ? 1 : 0) - (this.keys.has("down") ? 1 : 0);
    if (x !== 0 || y !== 0) {
      const length = Math.hypot(x, y);
      x /= length;
      y /= length;
    } else if (Math.hypot(this.stick.x, this.stick.y) > DEAD_ZONE) {
      x = this.stick.x;
      y = this.stick.y;
    }
    // The first move of the stick or of a key.
    if ((x !== 0 || y !== 0) && this.handlers.moved) this.handlers.moved();
    this.x = x;
    this.y = y;
  }
}
