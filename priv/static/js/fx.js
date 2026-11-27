// Things that show for a moment: a ring on the water at a lock, and the point of light
// that flies from a locked body to the new body of its player.

import { MESH_STRIDE } from "./state.js";
import { WATER_DEPTH } from "./geometry.js";

const RIPPLE_SECONDS = 0.9;

export class Effects {
  constructor(renderer) {
    this.renderer = renderer;
    this.ripples = [];
    this.lights = [];
    this.rippleData = new Float32Array(MESH_STRIDE * 64);
    this.lightData = new Float32Array(MESH_STRIDE * 64);
  }

  // A ring goes out on the water from a point, from the time `start`.
  ripple(x, z, start) {
    if (this.ripples.length < 24) this.ripples.push({ x, z, start });
  }

  // A point of light flies from a point to a point in `seconds`. Returns the light.
  light(from, to, color, start, seconds = 0.4) {
    const light = { from, to, color, start, seconds };
    if (this.lights.length < 12) this.lights.push(light);
    return light;
  }

  // The place of a light at a time: [x, y, z], or null after its end.
  lightAt(light, time) {
    const part = (time - light.start) / light.seconds;
    if (part >= 1) return null;
    const t = Math.max(0, part);
    // The light starts fast and gets slower: the eye can follow it.
    const ease = 1 - (1 - t) * (1 - t);
    const distance = Math.hypot(light.to[0] - light.from[0], light.to[1] - light.from[1]);
    return [
      light.from[0] + (light.to[0] - light.from[0]) * ease,
      0.35 + Math.min(1.6, 0.5 + distance * 0.22) * Math.sin(ease * Math.PI),
      light.from[1] + (light.to[1] - light.from[1]) * ease,
    ];
  }

  // Makes the lists of the picture for the time `time`.
  update(time) {
    let r = 0;
    this.ripples = this.ripples.filter((ripple) => time - ripple.start < RIPPLE_SECONDS);
    for (const ripple of this.ripples) {
      const part = (time - ripple.start) / RIPPLE_SECONDS;
      if (part < 0) continue;
      // Two rings, one after the other.
      for (const late of [0, 0.28]) {
        const t = part - late;
        if (t <= 0) continue;
        const size = 0.55 + 1.5 * t;
        this.rippleData.set([ripple.x, -WATER_DEPTH + 0.02, ripple.z, 0, size, 1, size, 1, 1, 1, 0.75 * (1 - t / (1 - late)) ** 1.5], r * MESH_STRIDE);
        r++;
      }
    }
    this.renderer.fill("ripples", this.rippleData, r);

    let l = 0;
    this.lights = this.lights.filter((light) => time - light.start < light.seconds + 0.25);
    for (const light of this.lights) {
      // The point of light and a short tail after it.
      for (let tail = 0; tail < 5; tail++) {
        const at = this.lightAt(light, time - tail * 0.028);
        if (!at) continue;
        const size = 0.34 - tail * 0.05;
        const [red, green, blue] = light.color;
        this.lightData.set([at[0], at[1], at[2], 0, size, size, size, 0.25 + 0.75 * red, 0.25 + 0.75 * green, 0.25 + 0.75 * blue, 1 - tail * 0.18], l * MESH_STRIDE);
        l++;
      }
      // At the end, the light opens at the new body.
      const after = time - light.start - light.seconds;
      if (after >= 0) {
        const size = 0.3 + after * 2.4;
        const [red, green, blue] = light.color;
        this.lightData.set([light.to[0], 0.3, light.to[1], 0, size, size * 0.6, size, 0.5 + 0.5 * red, 0.5 + 0.5 * green, 0.5 + 0.5 * blue, 1 - after / 0.25], l * MESH_STRIDE);
        l++;
      }
    }
    this.renderer.fill("lights", this.lightData, l);
  }
}
