// The signs of the page. The screen has no sentences: signs, numbers and names only.
// Each sign is a small drawing in SVG, made here. There are no image files.

const svg = (body, extra = "") => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ${extra}>${body}</svg>`;

// One body, from above: three parts and six legs.
const BODY = '<ellipse cx="12" cy="5.2" rx="2.6" ry="2.4" fill="currentColor"/><ellipse cx="12" cy="11" rx="2.2" ry="2.6" fill="currentColor"/><ellipse cx="12" cy="18" rx="3.6" ry="4.4" fill="currentColor"/><path stroke-width="1.6" d="M10 9.5 5 7M14 9.5l5-2.5M9.8 11H4.5M14.2 11h5.3M10 12.6 5.5 16M14 12.6l4.5 3.4"/>';

export const SIGNS = {
  // A spare body.
  body: svg(BODY),
  // Food: three pieces.
  food: '<svg viewBox="0 0 24 24"><circle cx="8" cy="15" r="5" fill="#ffbd33"/><circle cx="16" cy="15.5" r="4.4" fill="#ffc94d"/><circle cx="12.5" cy="8.5" r="4.6" fill="#ffd76a"/></svg>',
  // Lock: two bodies that hold each other.
  lock: '<svg viewBox="0 0 48 30" fill="currentColor" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><ellipse cx="12" cy="15" rx="7" ry="5"/><ellipse cx="36" cy="15" rx="7" ry="5"/><path fill="none" d="M17 11.5 24 9l7 2.5M17 18.5 24 21l7-2.5M19 15h10M7 10.5 4 6M7 19.5 4 24M41 10.5 44 6M41 19.5 44 24"/></svg>',
  // A river: waves.
  river: svg('<path d="M2 8c3-3 5 3 8 0s5 3 8 0 3 1 4 0M2 15c3-3 5 3 8 0s5 3 8 0 3 1 4 0"/>'),
  // Time.
  clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2.5"/>'),
  // Bodies that went across a body.
  steps: svg('<path d="M4 18 9 13M9 18l5-5M14 18l5-5M15 7l4-1-1 4" />'),
  // A new random name: two arrows that change places.
  shuffle: svg('<path d="M3 7h4c4 0 6 10 10 10h4M18 14l3 3-3 3M3 17h4c1.6 0 2.9-1.6 4-3.6M13 9.6c1.1-1.6 2.4-2.6 4-2.6h4M18 4l3 3-3 3"/>'),
  // The story.
  story: svg('<path d="M3 16c2.5-6 15.5-6 18 0"/><path d="M6.5 13v5M10.5 11.6V18M13.5 11.6V18M17.5 13v5"/>'),
  soundOn: svg('<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5z" fill="currentColor"/><path d="M15.5 9a4.5 4.5 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11"/>'),
  soundOff: svg('<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5z" fill="currentColor"/><path d="m16 9.5 5 5M21 9.5l-5 5"/>'),
  save: svg('<path d="M12 4v11M7.5 11 12 15.5 16.5 11M5 19.5h14"/>'),
  again: svg('<path d="M5 12a7 7 0 1 1 2.2 5.1"/><path d="M4.5 18.5 5 14l4.5.6"/>'),
  close: svg('<path d="m6 6 12 12M18 6 6 18"/>'),
  // The arrow. It points up: the page turns it.
  arrow: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2 21 14h-6v8H9v-8H3z"/></svg>',
  // An open cell.
  cell: svg('<path d="M12 3 20 7.5v9L12 21 4 16.5v-9z"/>'),
  // The nest: a hole in a ring of earth.
  nest: svg('<ellipse cx="12" cy="14" rx="9" ry="5.5"/><ellipse cx="12" cy="14" rx="4" ry="2.2" fill="currentColor"/>'),
  // The page waits for the server.
  wait: svg('<path d="M12 3a9 9 0 1 0 9 9"/>'),
  // Keys.
  move: svg('<path d="M12 3v18M3 12h18M9 6l3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3"/>'),
};

// Puts a sign into each element that has the attribute data-sign.
export function putSigns(root) {
  for (const element of root.querySelectorAll("[data-sign]")) {
    element.insertAdjacentHTML("afterbegin", SIGNS[element.dataset.sign] || "");
  }
}

// A sign as a new element.
export function sign(name) {
  const element = document.createElement("i");
  element.className = "sign";
  element.innerHTML = SIGNS[name];
  return element;
}
