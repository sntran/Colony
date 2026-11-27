# Colony

Colony is a multiplayer game in a browser. Each player controls one small creature: a
**body**. One body cannot cross a river. Many bodies can: a body **locks** to the edge of
the land or to a locked body, and the locked bodies make a bridge.

This repo has the fourth version of the prototype. "Colony" is a working name.

- **The players are the bridge.** When you lock your body, you leave it. The body stays in
  the bridge with your name. You then have the body of a **spare body** of the colony.
- **The world has no end.** It goes north: land, river, land, river. Each river is wider
  than the one before, up to 27 rows. The colony builds one bridge across each river, and
  the seasons change from land to land.
- The colony has two kinds of workers. **Carriers** are small and dark: they carry food
  from the piles to the nest, and a lock never uses them. **Spare bodies** are the size of
  the body of a player: they wait at the crossing place, and each lock uses one.
- **The guide** always shows one target: the nest if you carry food, the nearest open cell
  if the colony has a spare body, or the nearest pile with food.
- Players do not chat, and the screen has no sentences: signs, numbers and names only.
- A **crossing** is the moment when a bridge touches the next land. It makes a **record**
  of the bridge, with the names of its builders. The nest moves to the foot of the new
  bridge, and the next pile appears across the next river.
- **You are the same person for always** on your device: your bodies, your food and your
  name stay, also on a later day.
- All things in the world come from code. There are no model, image, sound or font files.

| | Plan | Report of the tests |
|---|---|---|
| Fourth version | [`0004-the-road-north.md`](docs/plans/0004-the-road-north.md) | [`docs/playtests/0004-the-road-north.md`](docs/playtests/0004-the-road-north.md) |
| Third version | [`0003-the-crossing.md`](docs/plans/0003-the-crossing.md) | [`docs/playtests/0003-the-crossing.md`](docs/playtests/0003-the-crossing.md) |
| Second version | [`0002-players-are-the-bridge.md`](docs/plans/0002-players-are-the-bridge.md) | [`docs/playtests/0002-players-are-the-bridge.md`](docs/playtests/0002-players-are-the-bridge.md) |
| First version | [`0001-first-prototype.md`](docs/plans/0001-first-prototype.md) | [`docs/playtests/0001-first-prototype.md`](docs/playtests/0001-first-prototype.md) |

The decisions that the plans do not make are in [`docs/decisions.md`](docs/decisions.md).
The rules of the versions before are on the branches `feat/0001-first-prototype`,
`feat/0002-players-are-the-bridge` and `feat/0003-the-crossing`.

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
2. Set the branch that has the game (the default is `feat/0004-the-road-north`), the
   minutes (60 by default, 120 at most) and the number of helpers. The game does not use
   the number of workers: the config has the carriers and the spare bodies.
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
| Your panel: your color, your name, your bodies, your food and the walks on your bodies | Click your name | Tap your name |
| A new random name | Click the button with the two arrows in your panel | Tap the button with the two arrows in your panel |
| The story | Click the button with the bridge sign | Tap the button with the bridge sign |
| Sound on and off | Click the button with the speaker sign | Tap the button with the speaker sign |

The game has one stick and one button. Follow the mark of the guide: two rings in your
color on your target. When the target is not on the screen, the arrow at the edge shows
the way on foot, with the sign of the target.

- **The guide** takes the first rule that applies: you carry food: the nest. The colony
  has a spare body: the nearest open cell. A pile with food that you can walk to: the
  nearest pile. Nothing: the button shows "wait".
- **Share the work.** If the colony has fewer spare bodies than players and your last act
  was a lock, the pile comes before the open cell. After you bring food, the open cell
  comes first again. A player alone always has the open cell first.
- **The button** shows the first state that applies: the food sign (you carry food, and a
  body with food cannot lock), the body sign with 0 (the colony has no spare body), a ring
  that fills in 1 second (your new body rests), the lock sign bright (tap it), the lock
  sign not bright (your cell does not touch an open cell).
- An **open cell** is a river cell where a lock is possible and helps. When the bridge
  must get wider, the cells that help the most are bright, and the others are weak. With
  no spare body, the open cells have a weak grey edge.
- **The moment of a lock.** Your body goes down into the cell, and its legs go to the
  bodies and the land that it touches. A note plays. A point of light flies to your new
  body: the nearest spare body. The camera follows the light.
- **The top of the screen** shows the number of spare bodies and the food at the nest.
  5 units of food make 1 spare body.
- **Carry food.** Go to a pile that you can walk to. Your body takes 10 units. At the
  nest, the units go into the nest, and the new spare bodies come out.
- **A pile** pays for the next bridge. Until the crossing to its land, it loses 1 unit each
  second, down to its least number: its number is red. Thus a fast bridge gives more food.
- **The crossing.** The camera shows the full bridge, and the song of the bridge plays.
  The record shows the river, the bodies and the bodies of the best bridge, the names with
  their bodies and their food, the food that was left in the pile, and the seconds. The
  nest moves to the foot of the new bridge, the carriers carry white eggs there, and the
  old nest stays as a mark with the number of its land. The story button flashes.
- **The story** shows all the locked bodies again in the order of their times, then the
  full world from above with the names, their bodies, their food and the walks on their
  bodies. A button saves that picture as a PNG file. The picture of a long world is tall.
- **The world stops** when no player is in it. A page that only looks is not a player.

A **helper** is a body that the server controls with the rules of a player. It is grey,
and its name is "Helper 1", "Helper 2" and so on. `COLONY_HELPERS` sets the number.

### Options in the address

- `?story=1` shows the story with no body in the world.
- `?demo=1` shows the story one time, then the live world with a slow camera from the
  nest to the next river. It adds no helper.
- `?stats=1` shows the frames each second, the frame time, the number of bodies, the delay
  to the server, the bytes each second and the number of pixels.
- `?scale=1` sets the number of canvas pixels for each page pixel. Without it, the page
  uses 2 at most, and fewer if a frame takes more than 20 milliseconds for 2 seconds.

## Config

All the numbers of the game are in [`config/game.exs`](config/game.exs): the size of the
grid, the rivers, the nest, the table of the bridges, the piles, the support rule, the
carriers, the spare bodies, the helpers, the scent and the save file. Start the server
again after a change.

These values from the environment change the config for one run:

| Name | Meaning |
|---|---|
| `PORT` | The port of the server. The default is 4000. |
| `COLONY_CARRIERS` | The number of carriers at the start. The default is 12. |
| `COLONY_SPARE` | The number of spare bodies at the start. The default is 10. |
| `COLONY_HELPERS` | The number of helpers. The default is 0. |
| `COLONY_SEED` | The seed of the lands and of the rivers for a new world. |
| `COLONY_SAVE_FILE` | The path of the save file. |

## Save

The server saves the world to `priv/data/world.bin` each 30 seconds, when the last player
goes, and when it stops. It saves all the world: the seed, the rivers, the locked bodies
with names, times, owners and walks, the nest and the old nests, the carriers and the
spare bodies, the scent, the piles, the food, the persons and their numbers, and the
records. It loads the file at the start.

A new world starts only with a new save file. The server does not load a save file of an
older version: it gives that file a new name, for example `world.bin.v4`, and starts a new
world.

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

To make the table of the bridges again (the bodies of a bridge across each width):

```sh
mix colony.table --runs 200
```

## Test

### Automatic tests

```sh
mix test
```

The tests run the world with no browser. They show the results that the plan asks for:

1. Twenty bodies lock as fast as the rules permit for 5 minutes. The carriers never
   decrease, and food comes to the nest all the time while a pile has food.
2. The nest moves at each crossing. The carriers and the spare bodies get to the new
   place. A player with food brings it to the new nest.
3. The sizes and the least units of the piles, from the table of the bridges.
4. With no player, the world does not change in 10 minutes. With a page that only looks,
   the same.
5. The order of the rules of the guide, and the rule "share the work". The guide of the
   page is the same as the guide of the server.
6. A player with food cannot lock.
7. For 20 seeds and 20 rivers: the widths, no way around a river, and a pile and a start
   of a bridge for each river.
8. The table of the bridges for each width from 5 to 27: no run stops.
9. A new name changes all the bodies of the player. A second join with the same secret
   number is the same person.
10. Save and load keep the nest, the old nests, the two kinds of workers, the players and
    their numbers.
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

The task makes a long world first: 20 crossings or more and 2,000 locked bodies. Then it
runs 150 carriers, 200 spare bodies, 20 clients and 8 helpers for 5 minutes at 10 ticks
each second. It prints the tick time (median, 95th and 99th percentile), the memory, and
the bytes each second for each client. For a short run: `mix colony.load --seconds 30`.

### Play test

Play in a real browser. The steps and the last results are in the report in
`docs/playtests/`.

The scripts in `test/play/` do the play tests of the plan. They need Node.js 22 or newer
and Playwright. Stop your server first: the scripts use port 4000.

```sh
npm install playwright
npx playwright install chromium
node test/play/run.mjs                 # all the browser tests
node test/play/run.mjs slow bodies     # some tests
node test/play/fast.mjs 20 10 2027     # 20 fast clients for 10 minutes, seed 2027
```

| Test | What it does |
|---|---|
| `slow` | One slow new player for 15 minutes (play test 1). |
| `fast.mjs` | 1, 5 or 20 fast new players with no browser for 10 minutes (play test 2). |
| `deadscreen` | 4 carriers, 3 spare bodies and one fast player for 3 minutes (play test 3). |
| `bodies` | A player locks 5 bodies, takes a new name and loads the page again (play test 4). |
| `two` | Two browsers: the same records, the same story and the same marks (play test 5). |
| `longworld` | 20 fast clients for 20 minutes, then a browser opens the game and the story (play test 6). |
| `shots` | The screenshots of the report. |

`SEEDS=2027,11,42` sets the seeds. The browser tests run in Chromium at 390 x 844, with
real touch events: one thumb stays on the stick while the other thumb taps the button.

**The new player** is the script [`test/play/newplayer.mjs`](test/play/newplayer.mjs). It
knows only what a person sees: if the button shows the bright lock sign, tap it. If not,
push the stick in a straight line to the mark of the guide if it is on the screen, or in
the direction of the arrow. If the body did not move for 1 second, push to one side for
0.5 seconds, then to the other side. The slow script waits 6 seconds at the start, 0.5 to
1.1 seconds before each tap and 0.3 to 0.6 seconds after it. The clients with no browser
use the same script, and the code of the page for the world, the guide and the button.

## The code

| Path | Contents |
|---|---|
| `config/game.exs` | All the numbers of the game. |
| `lib/colony/grid.ex` | The grid of hexagonal cells: the lands and the rivers. |
| `lib/colony/support.ex` | The support rule and the open cells. |
| `lib/colony/world.ex` | The state of the world and its step. It has no process and no clock. |
| `lib/colony/workers.ex` | The rules of the workers. |
| `lib/colony/helpers.ex` | The rules of the helpers. A helper obeys the guide. |
| `lib/colony/guide.ex` | The guide: the one target of a player. |
| `lib/colony/table.ex` | The table of the bridges: the bodies of a bridge across each width. |
| `lib/colony/protocol.ex` | The binary messages. |
| `lib/colony/store.ex` | The save file. |
| `lib/colony/server.ex` | The process that moves the world 10 times each second. |
| `lib/colony_web/` | The Phoenix endpoint, the channel and the plug that sends the page. |
| `lib/mix/tasks/` | `mix colony.reset`, `mix colony.records`, `mix colony.load`, `mix colony.table` and `mix colony.contracts`. |
| `specs/` | The contracts of the world in TLA+, and their models. |
| `priv/static/` | The page: one HTML file and JavaScript modules. It has no build step. |
| `priv/static/js/state.js` | The world as the page knows it, from the messages. |
| `priv/static/js/guide.js`, `player.js` | The guide, the arrow, the button, the cell for a lock and the body of the player. They use no page. |
| `priv/static/js/render.js`, `geometry.js`, `fx.js` | The picture: WebGL2 and the shapes. |
| `priv/static/js/sound.js` | The sound: the Web Audio API. |
| `priv/static/js/story.js` | The story and its picture. |
| `scripts/play_session.sh` | The server and the tunnel of a play session. |
| `test/` | The automatic tests. `test/play/` has the play tests. |

The rules for a change are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
