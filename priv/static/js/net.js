// The connection to the server: one Phoenix channel.
//
// The server sends binary messages. lib/colony/protocol.ex tells the format.

import { Socket } from "/vendor/phoenix.mjs";

export class Net {
  // handlers: snapshot(buffer), tick(buffer), you(message), records(list), record(record), status(text)
  constructor(name, demo, handlers) {
    this.handlers = handlers;
    this.bytes = 0;
    this.delay = 0;
    this.ready = false;

    this.socket = new Socket("/socket", {});
    this.socket.onOpen(() => handlers.status(""));
    this.socket.onError(() => handlers.status("No connection. The page tries again."));
    this.socket.onClose(() => {
      this.ready = false;
      handlers.status("No connection. The page tries again.");
    });
    this.socket.connect();

    this.channel = this.socket.channel("world", { name, demo });
    // Each message has about 13 bytes more than its data: the headers of the channel and of
    // the WebSocket frame. The count of bytes includes them.
    this.channel.on("s", (buffer) => {
      this.bytes += buffer.byteLength + 13;
      this.ready = true;
      handlers.snapshot(buffer);
    });
    this.channel.on("t", (buffer) => {
      this.bytes += buffer.byteLength + 13;
      handlers.tick(buffer);
    });
    this.channel.on("you", (message) => handlers.you(message));
    this.channel.on("records", (message) => handlers.records(message.records));
    this.channel.on("record", (record) => handlers.record(record));
    this.channel.onError(() => {
      this.ready = false;
    });
    this.channel
      .join()
      .receive("error", () => handlers.status("The server refused the connection."));
  }

  // Sends the position of the body. `move` is an ArrayBuffer of 6 bytes.
  move(buffer) {
    if (this.ready) this.channel.push("m", buffer);
  }

  // Sends a question and returns a promise of the reply, or of null.
  ask(event, payload) {
    return new Promise((resolve) => {
      if (!this.ready) return resolve(null);
      this.channel
        .push(event, payload, 3000)
        .receive("ok", (reply) => resolve(reply || {}))
        .receive("error", () => resolve(null))
        .receive("timeout", () => resolve(null));
    });
  }

  // Asks for a lock. The reply is the new body of the player, or null if the lock is not
  // possible: { x, z, worker } for the body of a worker, { wait } with no free worker.
  lock(cell, at) {
    return this.ask("lock", { cell, at });
  }

  // Asks for the data of a locked body: { name, helper, time, crossings }, or null.
  body(cell) {
    return this.ask("body", { cell });
  }

  // Measures the time of a message to the server and back.
  ping() {
    if (!this.ready) return;
    const start = performance.now();
    this.channel.push("ping", {}, 5000).receive("ok", () => {
      this.delay = performance.now() - start;
    });
  }

  // The bytes from the server after the last call of this function.
  takeBytes() {
    const bytes = this.bytes;
    this.bytes = 0;
    return bytes;
  }
}

export function encodeMove(x, z, heading, scent) {
  const buffer = new ArrayBuffer(6);
  const view = new DataView(buffer);
  const position = (value) => Math.max(0, Math.min(65535, Math.round((value + 1) * 1000)));
  const turn = Math.round((heading / (2 * Math.PI)) * 256);
  view.setUint16(0, position(x), true);
  view.setUint16(2, position(z), true);
  view.setUint8(4, ((turn % 256) + 256) % 256);
  view.setUint8(5, scent ? 1 : 0);
  return buffer;
}

export function toBase64(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}
