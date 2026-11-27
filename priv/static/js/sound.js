// The sound of the game. The Web Audio API makes each sound: there are no sound files.
//
// The sound starts at the first touch. If the browser gives no sound, no function here
// does anything, and no function gives an error.

// A scale of five notes, as steps of half a tone.
const SCALE = [0, 2, 4, 7, 9];
// The lowest note of each river, as a MIDI number: each river has its own key. A longer
// river has a lower key: its last rows are then not too high.
const KEYS = [55, 50, 46, 43];
// The page plays this many lock notes each second at most. Thus the sound does not hurt
// with 20 players.
const NOTES_EACH_SECOND = 8;
const SMALL_EACH_SECOND = 4;
const STORE = "colony.sound";

const frequency = (midi) => 440 * 2 ** ((midi - 69) / 12);

// The note of a row of a river: a higher row is a higher note.
export function noteOf(river, row) {
  const index = Math.max(0, row - 1);
  return KEYS[(Math.max(1, river) - 1) % KEYS.length] + 12 * Math.floor(index / SCALE.length) + SCALE[index % SCALE.length];
}

export class Sound {
  constructor() {
    this.context = null;
    this.failed = false;
    this.on = true;
    try {
      this.on = localStorage.getItem(STORE) !== "off";
    } catch (_) {
      // The page cannot read the store. The sound is on.
    }
    // The numbers of the sounds that the page played. A test reads them.
    this.counts = { locks: 0, story: 0, songs: 0, songNotes: 0, chords: 0, dropped: 0, food: 0, workers: 0, none: 0, steps: 0 };
    this.recent = [];
    this.recentSmall = [];
    this.waterLevel = 0;
  }

  // Starts the sound. The page calls this at the first touch and at the first key.
  start() {
    if (this.context || this.failed) {
      if (this.context && this.context.state === "suspended") this.context.resume().catch(() => {});
      return;
    }
    try {
      const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!Context) throw new Error("no sound");
      const context = new Context();
      this.master = context.createGain();
      this.master.gain.value = this.on ? 1 : 0;
      this.master.connect(context.destination);

      // Water: noise through a filter, in a loop.
      const seconds = 2;
      const buffer = context.createBuffer(1, context.sampleRate * seconds, context.sampleRate);
      const data = buffer.getChannelData(0);
      let last = 0;
      for (let i = 0; i < data.length; i++) {
        // Noise with more low sound than high sound.
        last = last * 0.82 + (Math.random() * 2 - 1) * 0.18;
        data[i] = last * 3;
      }
      this.noise = buffer;
      const source = context.createBufferSource();
      source.buffer = buffer;
      source.loop = true;
      const filter = context.createBiquadFilter();
      filter.type = "bandpass";
      filter.frequency.value = 520;
      filter.Q.value = 0.5;
      this.water = context.createGain();
      this.water.gain.value = 0;
      source.connect(filter).connect(this.water).connect(this.master);
      source.start();
      this.context = context;
      if (context.state === "suspended") context.resume().catch(() => {});
    } catch (_) {
      // This browser gives no sound. The game continues with no sound.
      this.failed = true;
      this.context = null;
    }
  }

  // Stops or starts the sound. Returns true if the sound is on.
  toggle() {
    this.on = !this.on;
    try {
      localStorage.setItem(STORE, this.on ? "on" : "off");
    } catch (_) {
      // The page cannot write the store.
    }
    if (this.context) this.master.gain.setTargetAtTime(this.on ? 1 : 0, this.context.currentTime, 0.03);
    return this.on;
  }

  ready() {
    return this.context !== null && this.on;
  }

  // One note: a soft tone that starts fast and fades.
  note(midi, volume, length, delay = 0) {
    if (!this.ready()) return;
    const context = this.context;
    const start = context.currentTime + delay;
    const gain = context.createGain();
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0002, volume), start + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + length);
    gain.connect(this.master);
    for (const [type, times, part] of [["triangle", 1, 1], ["sine", 2, 0.35], ["sine", 3, 0.12]]) {
      const tone = context.createOscillator();
      tone.type = type;
      tone.frequency.value = frequency(midi) * times;
      const level = context.createGain();
      level.gain.value = part;
      tone.connect(level).connect(gain);
      tone.start(start);
      tone.stop(start + length + 0.05);
    }
  }

  // True if one more sound of a kind can play now.
  room(list, limit) {
    const now = performance.now();
    while (list.length > 0 && now - list[0] > 1000) list.shift();
    if (list.length >= limit) return false;
    list.push(now);
    return true;
  }

  // A lock: one note. `near` is from 0 (far) to 1 (the lock of this player). The lock of
  // this player always plays.
  // `kind` is "locks" for a lock in the game, or "story" for a body of the story.
  lock(river, row, near, kind = "locks") {
    if (!this.ready()) return;
    if (!this.room(this.recent, NOTES_EACH_SECOND) && near < 1) {
      this.counts.dropped++;
      return;
    }
    this.counts[kind]++;
    this.note(noteOf(river, row), 0.05 + 0.2 * near, 0.7);
  }

  // A crossing: the notes of the bridge again, fast, in the order of the locks: the song
  // of the bridge. Then one chord. `rows` has the row of each body.
  song(river, rows, volume = 1) {
    if (!this.ready() || rows.length === 0) return;
    const step = Math.min(0.09, 2.2 / rows.length);
    rows.forEach((row, index) => this.note(noteOf(river, row), 0.16 * volume, 0.45, index * step));
    const key = KEYS[(river - 1) % KEYS.length];
    const end = rows.length * step + 0.12;
    for (const tone of [0, 7, 12, 16, 19]) this.note(key + tone, 0.13 * volume, 2.4, end);
    this.counts.songs++;
    this.counts.songNotes += rows.length;
    this.counts.chords++;
  }

  // Water: louder near a river. `level` is from 0 to 1.
  setWater(level) {
    if (!this.context) return;
    if (Math.abs(level - this.waterLevel) < 0.02) return;
    this.waterLevel = level;
    this.water.gain.setTargetAtTime(0.22 * level, this.context.currentTime, 0.4);
  }

  // A short sound of noise.
  tick(volume, pitch, length) {
    if (!this.ready()) return;
    const context = this.context;
    const source = context.createBufferSource();
    source.buffer = this.noise;
    const filter = context.createBiquadFilter();
    filter.type = "bandpass";
    filter.frequency.value = pitch;
    filter.Q.value = 1.2;
    const gain = context.createGain();
    const start = context.currentTime;
    gain.gain.setValueAtTime(volume, start);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + length);
    source.connect(filter).connect(gain).connect(this.master);
    source.start(start, Math.random() * 1.5, length + 0.02);
  }

  // A step of the body of this player: a very soft tick.
  step() {
    if (!this.ready()) return;
    this.counts.steps++;
    this.tick(0.05, 1500 + Math.random() * 700, 0.05);
  }

  // Food gets to the nest: a small sound. `near` is from 0 to 1.
  food(near) {
    if (!this.ready() || near <= 0.02 || !this.room(this.recentSmall, SMALL_EACH_SECOND)) return;
    this.counts.food++;
    this.note(88 + Math.floor(Math.random() * 3) * 2, 0.05 * near, 0.18);
  }

  // The nest makes a worker: a different small sound, two notes that go up.
  worker(near) {
    if (!this.ready() || near <= 0.02 || !this.room(this.recentSmall, SMALL_EACH_SECOND)) return;
    this.counts.workers++;
    this.note(67, 0.07 * near, 0.22);
    this.note(74, 0.07 * near, 0.3, 0.09);
  }

  // The colony has no spare body: a low sound.
  none() {
    if (!this.ready()) return;
    this.counts.none++;
    this.note(38, 0.3, 0.35);
    this.note(33, 0.3, 0.5, 0.12);
  }
}
