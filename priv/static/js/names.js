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
const SECRET = "colony.secret";

// The secret random number of this page. The page makes it one time and keeps it in local
// storage. The server knows the player by it: the same person on each load, also on a
// later day. Returns null if the browser has no local storage: then the server makes a new
// person at each load, as before.
export function mySecret() {
  try {
    let secret = localStorage.getItem(SECRET);
    if (!secret) {
      const bytes = new Uint8Array(16);
      crypto.getRandomValues(bytes);
      secret = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
      localStorage.setItem(SECRET, secret);
      // Some browsers accept the write and do not keep the value.
      if (localStorage.getItem(SECRET) !== secret) return null;
    }
    return /^[A-Za-z0-9]{16,64}$/.test(secret) ? secret : null;
  } catch (_) {
    return null;
  }
}

// The name stays in local storage. If storage is not available, the name is new at each load.
// The name of this player. It stays the same on this device.
export function myName() {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved) return saved;
  } catch (_) {
    // Continue with a new name.
  }
  return newName();
}

// A new random name for this player, for this device.
export function newName() {
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

// A spare body: the body that a player gets at a lock. It has the size of a player.
export const SPARE_COLOR = [0.4, 0.24, 0.13];

// A carrier: smaller and darker. A lock never uses a carrier.
export const CARRIER_COLOR = [0.11, 0.065, 0.04];

// A helper is grey: it is not a person.
export const HELPER_COLOR = [0.62, 0.64, 0.66];
