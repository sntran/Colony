# Colony

Colony is a multiplayer game in a browser. Each player controls one small creature: a
**body**. One body cannot cross a river. Many bodies can: a body **locks** to the edge of
the land or to a locked body, and the locked bodies make a bridge.

This repo has the third version of the prototype. "Colony" is a working name.

- **The players are the bridge.** When you lock your body, you leave it. The body stays in
  the bridge with your name. You then have the body of a **worker**.
- **The world has four rivers**, one after the other, each wider than the one before. The
  colony builds one bridge across each river.
- Workers are bodies that the server controls. A worker never locks. It smells the food and
  carries it to the nest. Each worker is a **spare body**: a lock uses one.
- Players do not chat, and the screen has no sentences: signs, numbers and names only.
- A **crossing** is the moment when a bridge touches the next land. It makes a **record**
  of the bridge, with the names of its builders.
- The world is complete when the first food of the last pile is at the nest. Then each
  page shows the **story**: all the locks in the order of their times, with the names.
- All things in the world come from code. There are no model, image, sound or font files.

| | Plan | Report of the tests |
|---|---|---|
| Third version | [`0003-the-crossing.md`](docs/plans/0003-the-crossing.md) | [`docs/playtests/0003-the-crossing.md`](docs/playtests/0003-the-crossing.md) |
| Second version | [`0002-players-are-the-bridge.md`](docs/plans/0002-players-are-the-bridge.md) | [`docs/playtests/0002-players-are-the-bridge.md`](docs/playtests/0002-players-are-the-bridge.md) |
| First version | [`0001-first-prototype.md`](docs/plans/0001-first-prototype.md) | [`docs/playtests/0001-first-prototype.md`](docs/playtests/0001-first-prototype.md) |

The decisions that the plans do not make are in [`docs/decisions.md`](docs/decisions.md).
The rules of the versions before are on the branches `feat/0001-first-prototype` and
`feat/0002-players-are-the-bridge`.

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
computer on the network. For players on other networks, use a play session.

## A play session

The workflow [`play-session.yml`](.github/workflows/play-session.yml) starts the server on
a runner of GitHub and opens a quick tunnel of Cloudflare to it. The job gets no secret.
The workflow file is on the branch `main`: GitHub starts a workflow by hand only from the
default branch. The game comes from the branch that you give.

1. On GitHub, open "Actions", then "Play session", then "Run workflow".
2. Set the branch that has the game (the default is `feat/0003-the-crossing`), the minutes
   (60 by default, 120 at most), the number of workers and the number of helpers.
3. Open the summary of the job. After about one minute and a half it has two addresses:
   the game and the story. Give the address of the game to the players.
4. At the end, the artifact of the run has the world file, the records of the bridges and
   the story as JSON, and the log of the server.

[`scripts/play_session.sh`](scripts/play_session.sh) is the part that runs on the runner.
It also runs on a computer with Linux:

```sh
MINUTES=30 HELPERS=2 sh scripts/play_session.sh
```

## Play

| | Keys | Touch |
|---|---|---|
| Move | Arrow keys or W, A, S, D | The stick below the left thumb |
| Lock | Space | The button with the two bodies that hold each other |
| Name, time and count of a locked body | Click the body | Tap the body |
| A new random name | Click your name | Tap your name |
| The story | Click the button with the bridge sign | Tap the button with the bridge sign |
| Sound on and off | Click the button with the speaker sign | Tap the button with the speaker sign |

The game has one stick and one button. Push the stick to the river. The workers are there
before you: they wait where the bridge must start.

- An **open cell** is a river cell where a lock is possible and helps. Each open cell has
  a bright edge that moves. When an open cell touches the cell of your body, the button
  is bright: tap it.
- **The moment of a lock.** Your body goes down into the cell, and its legs go to the
  bodies and the land that it touches. A note plays. A point of light flies to your new
  body: the body of the nearest worker. The camera follows the light.
- **A lock uses one spare body.** The top of the screen shows the number of spare bodies
  and the food at the nest. With no spare body, the button is not bright and the number
  flashes. The nest makes 1 worker for each 3 units of food.
- **Forward first.** A bridge goes forward, one body wide, for 7 rows. Then it has no more
  support. Then cells beside the bridge are open: each body beside a body helps. When the
  bridge can go forward again, only the cells in front are open.
- **The arrow** at the edge of the screen shows the way on foot: to the nearest open cell
  if the colony has a spare body; to the nest if you carry food; to a pile with food if
  the colony has no spare body.
- **Carry food.** Go to a pile that you can walk to. Your body takes 10 units. At the
  nest, the units go into the nest, and the new workers come out.
- **A pile** that no body can walk to loses 1 unit each second, down to 50: its number is
  red. Thus a fast bridge gives more food.
- **The crossing.** When the bridge touches the next land, the camera moves back and shows
  the full bridge, and the song of the bridge plays. The workers that waited go across in
  a line. The record shows: the river, the names with their bodies and their food, the
  food that was left in the pile, and the seconds. Then the light of the next pile appears.
- **The story** shows all the locked bodies again in the order of their times, then the
  full world from above with the names. A button saves that picture as a PNG file.

A **helper** is a body that the server controls with the rules of a player. It is grey,
and its name is "Helper 1", "Helper 2" and so on. `COLONY_HELPERS` sets the number.

### Options in the address

- `?story=1` shows the story with no body in the world.
- `?demo=1` shows the story one time, then the live world with a slow camera. It adds no
  helper.
- `?stats=1` shows the frames each second, the frame time, the number of bodies, the delay
  to the server, the bytes each second and the number of pixels.
- `?scale=1` sets the number of canvas pixels for each page pixel. Without it, the page
  uses 2 at most, and fewer if a frame takes more than 20 milliseconds for 2 seconds.

## Config

All the numbers of the game are in [`config/game.exs`](config/game.exs): the size of the
grid, the rivers, the piles, the support rule, the workers, the helpers, the scent and the
save file. Start the server again after a change.

These values from the environment change the config for one run:

| Name | Meaning |
|---|---|
| `PORT` | The port of the server. The default is 4000. |
| `COLONY_WORKERS` | The number of workers at the start. The default is 30. |
| `COLONY_HELPERS` | The number of helpers. The default is 0. |
| `COLONY_SEED` | The seed of the lands and of the rivers for a new world. |
| `COLONY_SAVE_FILE` | The path of the save file. |

## Save

The server saves the world to `priv/data/world.bin` each 30 seconds and when it stops. It
saves the seed, the locked bodies with names, times and counts, the number of workers,
the scent, the piles, the food, the records and the story. It loads the file at the start.

A new world starts only with a new save file. The server does not load a save file of an
older version: it gives that file the name `world.bin.v2` and starts a new world.

Stop the server with the signal `TERM` (for example `kill PID`), and it saves first. Two
times Ctrl+C stops the VM immediately: the world is then as it was at the last save.

To print the records and the story of the save file as JSON:

```sh
mix colony.records
```

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

1. With no player and no helper, no body locks in 5 minutes, and the workers wait at the
   crossing place of river 1.
2. One body locks 6 times across river 1. Food is at the nest in less than 20 seconds.
3. The table of the plan: the number of bodies for each width of a river.
4. A lock into a cell that is not open, and a lock with no spare body, get an error.
5. Two bodies lock into the same cell in the same tick: one gets the cell.
6. No way around: for 40 seeds, no body walks from a land to the next land with no bridge.
7. The piles: the place, the size, the loss, the limit of 50 units, and the next pile at
   the crossing.
8. A player carries 10 units to the nest, and the new workers are there.
9. Four helpers and no player complete the four crossings.
10. The world is complete at the first food of pile 4. Save and load keep the lands, the
    bodies, the records and the story.
11. The world obeys its contracts: see "Contracts" below.

### Contracts

The rules of the world are also in TLA+, in [`specs/`](specs/README.md). A TLA+ model
checker in Elixir ([accord](https://github.com/sntran/accord/tree/feat/native-tla-checker))
looks at all the states of small models of these contracts. Java is not necessary.

```sh
mix colony.contracts          # all the models, about 2 minutes
mix colony.contracts Bridge   # one model
```

`mix test` also puts a contract between a test player and the real world as a monitor.
Each message, each reply and each event of the world must be a step that the contract
permits.

### Load test

```sh
mix colony.load
```

The task runs 1,000 workers, 20 clients and 8 helpers for 5 minutes at 10 ticks each
second. It prints the tick time (median, 95th and 99th percentile), the memory, and the
bytes each second for each client. For a short run: `mix colony.load --seconds 30`.

### Play test

Play in a real browser. The steps and the last results are in the report in
`docs/playtests/`.

The scripts in `test/play/` do the play tests of the plan. They need Node.js 22 or newer
and Playwright. Stop your server first: the scripts use port 4000.

```sh
npm install playwright
npx playwright install chromium
node test/play/run.mjs              # all the tests
node test/play/run.mjs alone story  # some tests
```

| Test | What it does |
|---|---|
| `alone` | A new player alone, to the end of the world. It also counts the notes of the sound. |
| `story` | `/?story=1` on the world of the test `alone`, and the PNG file. |
| `carry` | A player who never locks, with 3 helpers, carries food 5 times. |
| `helpers` | One player and 3 helpers. |
| `two` | Two browsers: the same record and the same story. |
| `crowd` | 20 new players with no browser. |
| `sound` | A browser with no sound, and the sound button. |
| `moments` | The screenshots of the report. |

The browser tests run in Chromium at 390 x 844, with real touch events: one thumb stays on
the stick while the other thumb taps the button.

**The new player** is the script [`test/play/newplayer.mjs`](test/play/newplayer.mjs). It
knows only what a person sees: if the button is bright, tap it. If not, push the stick in
a straight line to the nearest open cell on the screen, or in the direction of the arrow.
If the body did not move for 1 second, push to one side, then to the other side. The 20
clients of the test `crowd` use the same script, and the code of the page for the world,
for the body and for the arrow.

## The code

| Path | Contents |
|---|---|
| `config/game.exs` | All the numbers of the game. |
| `lib/colony/grid.ex` | The grid of hexagonal cells: the lands and the rivers. |
| `lib/colony/support.ex` | The support rule and the open cells. |
| `lib/colony/world.ex` | The state of the world and its step. It has no process and no clock. |
| `lib/colony/workers.ex` | The rules of the workers. |
| `lib/colony/helpers.ex` | The rules of the helpers. |
| `lib/colony/protocol.ex` | The binary messages. |
| `lib/colony/store.ex` | The save file. |
| `lib/colony/server.ex` | The process that moves the world 10 times each second. |
| `lib/colony_web/` | The Phoenix endpoint, the channel and the plug that sends the page. |
| `lib/mix/tasks/` | `mix colony.reset`, `mix colony.records`, `mix colony.load` and `mix colony.contracts`. |
| `specs/` | The contracts of the world in TLA+, and their models. |
| `priv/static/` | The page: one HTML file and JavaScript modules. It has no build step. |
| `priv/static/js/state.js` | The world as the page knows it, from the messages. |
| `priv/static/js/guide.js`, `player.js` | The arrow, the cell for a lock and the body of the player. They use no page. |
| `priv/static/js/render.js`, `geometry.js`, `fx.js` | The picture: WebGL2 and the shapes. |
| `priv/static/js/sound.js` | The sound: the Web Audio API. |
| `priv/static/js/story.js` | The story and its picture. |
| `scripts/play_session.sh` | The server and the tunnel of a play session. |
| `test/` | The automatic tests. `test/play/` has the play tests. |

The rules for a change are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
