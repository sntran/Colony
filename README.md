# Colony

Colony is a multiplayer game in a browser. Each player controls one small creature: a
**body**. One body cannot cross a gap. Many bodies can: a body **locks** to the edge of the
ground or to a locked body, and the locked bodies make a bridge.

This repo has the first prototype. "Colony" is a working name.

- When you lock your body, you leave it. The body stays in the bridge with your name. You
  get a new body at the nest.
- **Workers** are bodies that the server controls. They obey simple rules.
- Players do not chat. You put **scent** on the ground, and the workers follow it.
- All things in the world come from code. There are no model, image, sound or font files.

The prototype must answer three questions:

1. Is it fun for one player to lock bodies and cross a gap?
2. Can workers build a bridge with a few simple rules?
3. Can the server hold 1,000 bodies at 10 ticks each second, and can a phone draw them?

The plan is [`docs/plans/0001-first-prototype.md`](docs/plans/0001-first-prototype.md).
The decisions that the plan does not make are in [`docs/decisions.md`](docs/decisions.md).
The report of the tests is
[`docs/playtests/0001-first-prototype.md`](docs/playtests/0001-first-prototype.md).

## Start

The server needs Erlang/OTP and Elixir. I get them from
[BEAM.com](https://github.com/sntran/BEAM.com): one file that is Erlang/OTP and Elixir.
Get the file of the newest release, and make links to it with the names `mix` and `iex`:

```sh
mkdir -p ~/.local/beam && cd ~/.local/beam
curl -fLO https://github.com/sntran/BEAM.com/releases/download/v0.1.0-rc.8/beam.com
chmod +x beam.com
ln -s beam.com mix
ln -s beam.com iex
export PATH="$HOME/.local/beam:$PATH"
```

Then get the packages and start the server:

```sh
mix local.hex --force
mix deps.get
mix phx.server
```

Open <http://localhost:4000>. To use a different port, set `PORT`:

```sh
PORT=8080 mix phx.server
```

To play on a phone, open `http://ADDRESS:4000`, where `ADDRESS` is the address of the
computer on the network.

## Play

| | Keys | Touch |
|---|---|---|
| Move | Arrow keys or W, A, S, D | The stick below the left thumb |
| Lock | Space | The button "Lock" |
| Scent | Hold Shift | Hold the button "Scent" |
| Name and time of a locked body | Click the body | Tap the body |

Go to the gap. The cells where a lock is possible show at your body. The button "Lock" is
bright when a lock is possible. One second after a lock, you have a new body at the nest.

A bridge one cell wide stops after 7 rows. Lock a body beside a body of the bridge to make
the bridge stronger. A locked body that is red and shakes has almost no support.

Hold "Scent" and go from the nest to the gap. The workers follow the scent, build a bridge
and carry food to the nest.

### Options in the address

- `?stats=1` shows the frames each second, the number of bodies, the delay to the server
  and the bytes each second.
- `?demo=1` runs with no input. Scent goes from the nest to the gap. The workers build the
  bridge and carry food. The camera moves slowly.
- `?scale=1` sets the number of canvas pixels for each page pixel. Without it, the page
  uses 2 at most, and fewer if the picture is slow.

## Config

All the numbers of the game are in [`config/game.exs`](config/game.exs): the size of the
grid, the support rule, the scent, the number of workers, the food and the save file.
Start the server again after a change.

These values from the environment change the config for one run:

| Name | Meaning |
|---|---|
| `PORT` | The port of the server. The default is 4000. |
| `COLONY_WORKERS` | The number of workers. The default is 200. |
| `COLONY_SEED` | The seed of the ground for a new world. |
| `COLONY_SAVE_FILE` | The path of the save file. |

## Save

The server saves the world to `priv/data/world.bin` each 30 seconds and when it stops. It
saves the seed, the locked bodies with names and times, the scent and the food. It loads
the file at the start.

Stop the server with the signal `TERM` (for example `kill PID`), and it saves first. Two
times Ctrl+C stops the VM immediately: the world is then as it was at the last save.

To start with a new world, stop the server, then:

```sh
mix colony.reset
```

## Test

### Automatic tests

```sh
mix test
```

The tests run the world with no browser. They show the results that the plan asks for:

1. A bridge one cell wide stops at 7 rows. A bridge two cells wide crosses 12 rows.
2. When a body falls, the bodies that lose their support fall also.
3. With 200 workers and scent from the nest to the gap, the workers complete a bridge and
   bring food in less than 5 minutes of world time.
4. When the scent goes away, all locked workers let go. Locked bodies of players stay if
   they have support.
5. Save and load give the same world.

### Load test

```sh
mix colony.load
```

The task runs 1,000 workers and 20 clients for 5 minutes at 10 ticks each second. It
prints the tick time (median, 95th and 99th percentile), the memory, and the bytes each
second for each client. For a short run: `mix colony.load --seconds 30`.

### Play test

Play in a real browser. The steps and the last results are in the report in
`docs/playtests/`. For the test with no workers:

```sh
COLONY_WORKERS=0 COLONY_SAVE_FILE=/tmp/alone.bin mix phx.server
```

The scripts in `test/play/` do the play tests of the plan in Chromium, with real touch
events and real key events. They start and stop the server, and they write the screenshots
of the report. They need Node.js and Playwright. Stop your server first: the scripts use
port 4000.

```sh
npm install playwright
npx playwright install chromium
node test/play/run.js
```

## The code

| Path | Contents |
|---|---|
| `config/game.exs` | All the numbers of the game. |
| `lib/colony/grid.ex` | The grid of hexagonal cells. |
| `lib/colony/support.ex` | The support rule. |
| `lib/colony/world.ex` | The state of the world and its step. It has no process and no clock. |
| `lib/colony/workers.ex` | The rules of the workers. |
| `lib/colony/protocol.ex` | The binary messages. |
| `lib/colony/store.ex` | The save file. |
| `lib/colony/server.ex` | The process that moves the world 10 times each second. |
| `lib/colony_web/` | The Phoenix endpoint, the channel and the plug that sends the page. |
| `lib/mix/tasks/` | `mix colony.reset` and `mix colony.load`. |
| `priv/static/` | The page: one HTML file and JavaScript modules. It draws with WebGL2. |
| `test/` | The automatic tests. |

The rules for a change are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
