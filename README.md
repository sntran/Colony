# Colony

Colony is a multiplayer game in a browser. Each player controls one small creature: a
**body**. One body cannot cross a river. Many bodies can: a body **locks** to the edge of
the bank or to a locked body, and the locked bodies make a bridge.

This repo has the second version of the prototype. "Colony" is a working name.

- **The players are the bridge.** When you lock your body, you leave it. The body stays in
  the bridge with your name. You then take the body of the nearest **worker**.
- Workers are bodies that the server controls. A worker never locks. It follows scent,
  carries food, and is a spare body for the players.
- Players do not chat. You put **scent** on the ground, and the workers follow it.
- A **pile** of food is on the far bank. When the first food of a pile gets to the nest,
  the game makes a **record** of the bridge, with the names of its builders.
- All things in the world come from code. There are no model, image, sound or font files.

This version must answer three questions:

1. Is it fun to be the bridge, alone, in the first 2 minutes?
2. Do 5 to 20 persons build together with no chat?
3. Does a person want to see the record of a bridge that has the name of that person?

| | Plan | Report of the tests |
|---|---|---|
| Second version | [`0002-players-are-the-bridge.md`](docs/plans/0002-players-are-the-bridge.md) | [`docs/playtests/0002-players-are-the-bridge.md`](docs/playtests/0002-players-are-the-bridge.md) |
| First version | [`0001-first-prototype.md`](docs/plans/0001-first-prototype.md) | [`docs/playtests/0001-first-prototype.md`](docs/playtests/0001-first-prototype.md) |

The decisions that the plans do not make are in [`docs/decisions.md`](docs/decisions.md).
The rules of the first version are on the branch `feat/0001-first-prototype`.

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

1. On GitHub, open "Actions", then "Play session", then "Run workflow".
2. Set the minutes (60 by default, 120 at most), the number of workers and the number of
   helpers.
3. Open the summary of the job. After about one minute it has the address. Give the
   address to the players.
4. At the end, the artifact of the run has the world file, the records of the bridges as
   JSON, and the log of the server.

GitHub shows the button "Run workflow" only when the workflow file is on the default
branch.

[`scripts/play_session.sh`](scripts/play_session.sh) is the part that runs on the runner.
It also runs on a computer with Linux:

```sh
MINUTES=30 HELPERS=2 sh scripts/play_session.sh
```

## Play

| | Keys | Touch |
|---|---|---|
| Move | Arrow keys or W, A, S, D | The stick below the left thumb |
| Lock | Space | The button "Lock" |
| Scent | Hold Shift | Hold the button "Scent" |
| Name, time and count of a locked body | Click the body | Tap the body |
| The list of the records | Click the button with the bridge sign | Tap the button with the bridge sign |

Go to the river. The far bank has a light where the pile is. The cells where a lock is
possible show at your body, and the button "Lock" is bright when a lock is possible.

Before a lock, marks on the river show the **reach**: one mark on each row that the bridge
can get to, if you lock there and then continue one body wide. A green mark on the far
bank tells that the bridge can get across. Select a cell beside a body, and the marks go
farther: each body beside a body helps.

After a lock, you have the body of the nearest worker that carries no food. The camera
goes to it. That body cannot lock for 1 second. If the colony has no worker that you can
get to, you get a new body at the nest after 3 seconds.

A bridge one body wide stops after 7 rows. Two bodies wide stops after 15 rows, and three
bodies wide after 23.

Hold "Scent" and go from the nest to the bridge. The workers follow the scent. They wait
at the end of the bridge, and they are your next bodies. When the bridge is complete, they
carry food to the nest.

The top of the page shows two numbers: the free workers (the bodies that the colony can
still use) and the food at the nest. The nest makes 1 worker for each 10 units of food.

A pile has 300 units. From the first lock, the pile loses 1 unit each second until the
first worker takes food. Thus a fast bridge gives more food. When a pile is empty, the
next pile appears across a wider place of the river.

At the first food of a pile, each player with a body in the bridge sees the record for 5
seconds: the names, the number of bodies of each name, the rows and the seconds.

A **helper** is a body that the server controls with the rules of a player. It is grey,
and its name is "Helper 1", "Helper 2" and so on. `COLONY_HELPERS` sets the number.

### Options in the address

- `?stats=1` shows the frames each second, the number of bodies, the delay to the server
  and the bytes each second.
- `?demo=1` runs with no input. Four helpers build a bridge to the pile, slowly. Then the
  workers carry food. The camera follows the helpers.
- `?scale=1` sets the number of canvas pixels for each page pixel. Without it, the page
  uses 2 at most, and fewer if the picture is slow.

## Config

All the numbers of the game are in [`config/game.exs`](config/game.exs): the size of the
grid, the river, the piles, the support rule, the workers, the helpers, the scent and the
save file. Start the server again after a change.

These values from the environment change the config for one run:

| Name | Meaning |
|---|---|
| `PORT` | The port of the server. The default is 4000. |
| `COLONY_WORKERS` | The number of workers at the start. The default is 30. |
| `COLONY_HELPERS` | The number of helpers. The default is 0. |
| `COLONY_SEED` | The seed of the ground and of the river for a new world. |
| `COLONY_SAVE_FILE` | The path of the save file. |

## Save

The server saves the world to `priv/data/world.bin` each 30 seconds and when it stops. It
saves the seed, the locked bodies with names, times and counts, the workers, the scent,
the pile, the food and the records. It loads the file at the start. A save file of the
first version gives a new world.

Stop the server with the signal `TERM` (for example `kill PID`), and it saves first. Two
times Ctrl+C stops the VM immediately: the world is then as it was at the last save.

To print the records of the save file as JSON:

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

1. With scent from the nest to the river and no player, no body locks in 5 minutes.
2. A bridge one body wide stops at 7 rows, two wide at 15, three wide at 23.
3. The calculation with integers gives the same result as a full calculation.
4. After a lock, the player has the body of the nearest free worker in the next tick.
   With no free worker, the player is at the nest after 3 seconds.
5. Ten units of food make one worker. With fewer than 5 free workers, the nest makes one
   worker each 10 seconds.
6. A pile loses units from the first lock to the first food. An empty pile makes the next
   pile at a wider place.
7. A record has the correct names, numbers and times. Save and load keep the records.
8. Four helpers complete the first bridge in less than 60 seconds of world time, and
   bring food across 12 rows in less than 5 minutes.
9. The world obeys its contracts: see "Contracts" below.

### Contracts

The rules of the world are also in TLA+, in [`specs/`](specs/README.md). A TLA+ model
checker in Elixir ([accord](https://github.com/sntran/accord/tree/feat/native-tla-checker))
looks at all the states of small models of these contracts. Java is not necessary.

```sh
mix colony.contracts          # all the models, about 20 seconds
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

The scripts in `test/play/` do the play tests of the plan in Chromium at 390 x 844, with
real touch events: one thumb stays on the stick while the other thumb taps "Lock" or holds
"Scent". They start and stop the server, and they write the screenshots of the report.
They need Node.js and Playwright. Stop your server first: the scripts use port 4000.

```sh
npm install playwright
npx playwright install chromium
node test/play/run.js              # all the tests
node test/play/run.js alone demo   # some tests: alone, helpers, two, demo
```

## The code

| Path | Contents |
|---|---|
| `config/game.exs` | All the numbers of the game. |
| `lib/colony/grid.ex` | The grid of hexagonal cells, and the river. |
| `lib/colony/support.ex` | The support rule and the reach. |
| `lib/colony/world.ex` | The state of the world and its step. It has no process and no clock. |
| `lib/colony/workers.ex` | The rules of the workers. |
| `lib/colony/helpers.ex` | The rules of the helpers. |
| `lib/colony/protocol.ex` | The binary messages. |
| `lib/colony/store.ex` | The save file. |
| `lib/colony/server.ex` | The process that moves the world 10 times each second. |
| `lib/colony_web/` | The Phoenix endpoint, the channel and the plug that sends the page. |
| `lib/mix/tasks/` | `mix colony.reset`, `mix colony.records`, `mix colony.load` and `mix colony.contracts`. |
| `specs/` | The contracts of the world in TLA+, and their models. |
| `priv/static/` | The page: one HTML file and JavaScript modules. It draws with WebGL2. |
| `scripts/play_session.sh` | The server and the tunnel of a play session. |
| `test/` | The automatic tests. `test/play/` has the play tests in a browser. |

The rules for a change are in [`CONTRIBUTING.md`](CONTRIBUTING.md).
