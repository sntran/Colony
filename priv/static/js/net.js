// The connection to the server: one Phoenix channel.
//
// The server sends binary messages. lib/colony/protocol.ex tells the format.

import { Socket } from "/vendor/phoenix.mjs";

export class Net {
  // handlers: snapshot(buffer), tick(buffer), you(message), records(list), record(record), status(text)
  // `look` is true for a client that only looks: it gets no body. `secret` is the secret
  // number of this page, or null.
  constructor(name, look, handlers, secret = null) {
    this.handlers = handlers;
    this.bytes = 0;
    this.delay = 0;
    this.ready = false;

    this.socket = new Socket("/socket", {});
    this.socket.onOpen(() => handlers.status(""));
    this.socket.onError(() => handlers.status("wait"));
    this.socket.onClose(() => {
      this.ready = false;
      handlers.status("wait");
    });
    this.socket.connect();

    this.channel = this.socket.channel("world", look ? { look: true } : secret ? { name, secret } : { name });
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
      .receive("error", () => handlers.status("wait"));
  }

  // Sends the position of the body. `move` is an ArrayBuffer of 7 bytes.
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

  // This player has a new name.
  rename(name) {
    return this.ask("name", { name });
  }

  // The numbers of this person: { name, bodies, food, walks }, or null.
  me() {
    return this.ask("me", {});
  }

  // The players with their bodies and their food, for the story.
  story() {
    return this.ask("story", {});
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
