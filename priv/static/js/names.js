// A random name for each browser, and a color from each name.

const FIRST = [
  "Amber", "Brisk", "Calm", "Clever", "Dusty", "Eager", "Fleet", "Gentle", "Happy", "Jolly",
  "Keen", "Little", "Lucky", "Merry", "Nimble", "Quick", "Quiet", "Red", "Sandy", "Steady",
  "Sunny", "Swift", "Tiny", "Wise",
];

const SECOND = [
  "Acorn", "Bark", "Berry", "Clover", "Dew", "Fern", "Leaf", "Moss", "Nettle", "Oak",
  "Pebble", "Petal", "Pine", "Reed", "Root", "Seed", "Sprout", "Stem", "Thorn", "Twig",
];

const KEY = "colony.name";

// The name stays in local storage. If storage is not available, the name is new at each load.
export function myName() {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved) return saved;
  } catch (_) {
    // Continue with a new name.
  }
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const name = `${pick(FIRST)} ${pick(SECOND)} ${10 + Math.floor(Math.random() * 90)}`;
  try {
    localStorage.setItem(KEY, name);
  } catch (_) {
    // The name is used for this load only.
  }
  return name;
}

function hash(text) {
  let value = 2166136261;
  for (let i = 0; i < text.length; i++) {
    value ^= text.charCodeAt(i);
    value = Math.imul(value, 16777619);
  }
  return value >>> 0;
}

function hsl(h, s, l) {
  const f = (n) => {
    const k = (n + h * 12) % 12;
    return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
  };
  return [f(0), f(8), f(4)];
}

const colors = new Map();

// The color of a player as [red, green, blue], each from 0 to 1.
export function colorOf(name) {
  let color = colors.get(name);
  if (!color) {
    const value = hash(name);
    // Bright colors. The workers are dark and the helpers are grey, thus a player is easy to see.
    color = hsl((value % 360) / 360, 0.78, 0.5 + ((value >>> 9) % 10) / 100);
    colors.set(name, color);
  }
  return color;
}

export function cssColor(color) {
  return `rgb(${color.map((part) => Math.round(part * 255)).join(",")})`;
}

// The plain color of all workers.
export const WORKER_COLOR = [0.2, 0.115, 0.075];

// A helper is grey: it is not a person.
export const HELPER_COLOR = [0.62, 0.64, 0.66];
