# Plan 0001: First prototype

This plan has all the decisions for the first prototype of Colony. Read all of it before you start. "Colony" is a working name.

## 1. The game in short

- Colony is a multiplayer game in a browser. Each player controls one small creature, as an ant. I call it a **body**.
- One body cannot cross a gap. Many bodies can. A body can **lock** to the edge of the ground or to a locked body. Locked bodies make a bridge.
- When a player locks a body, the player leaves that body. The body stays in the bridge with the name of the player. The player gets a new body at the nest.
- **Workers** are bodies that the server controls. They obey simple rules. They fill the colony when there are few players.
- Players do not chat. A player puts **scent** on the ground. Workers follow scent.
- All things in the world come from code. There are no model files and no image files.

Later plans add a cost for each body, a world that grows, and many more players. Do not build these now. Do not make them impossible.

## 2. What this prototype must tell me

1. Is it fun for one player to lock bodies and cross a gap, with no other players?
2. Can workers build a bridge with a few simple rules?
3. Can the server hold 1,000 bodies at 10 ticks each second? Can a phone draw them?

Build only what answers these questions.

## 3. Words

| Word | Meaning |
|---|---|
| body | One creature. A body is free or locked. |
| player | A person in a browser. A player controls one free body. |
| worker | A body that the server controls. |
| cell | One hexagon of the world grid. One cell holds one locked body. |
| row | A line of cells parallel to the banks. |
| bank | The ground on one side of the gap. |
| gap | The cells between the two banks. A free body cannot go there. |
| nest | The start point on the near bank. |
| support | A number that tells if a locked body can stay in the bridge. |
| scent | A number from 0 to 100 on a cell. |
| tick | One step of the server. There are 10 ticks each second. |

## 4. Decisions

### 4.1 Stack

- Use Erlang/OTP, Elixir and Phoenix. Use the latest stable versions.
- Get Erlang/OTP and Elixir from the release binary of BEAM.com (`sntran/BEAM.com`). Make links to it with the names `mix` and `iex`.
- Run on the native BEAM. Do not use the WebAssembly target in this plan. I think the load is too high for that target now.
- Use only Erlang and Elixir on the server. Do not use a NIF or a port. A later plan can then try the WebAssembly target.
- Do not use a database.
- The server holds the truth. The client draws the world and sends input.
- Use a Phoenix channel. Send the world state as binary data.
- The client is one page. Draw with WebGL2 on a canvas. Do not use a game engine.
- One command starts the server: `mix phx.server`. The server reads the port from `PORT`.

### 4.2 World

- The world is flat. It is a grid of hexagonal cells.
- Each cell touches two cells in its row, two cells in the row before, and two cells in the row after.
- The grid is 60 cells wide. It has 14 rows of near bank, 12 rows of gap, and 14 rows of far bank.
- The nest is on the near bank. A pile of 500 units of food is on the far bank, 4 rows from the gap. The player must see the food from the near bank.
- Make the ground, the grass and the stones from a seed.
- A free body moves smoothly at 4 cells each second. It can go on bank cells and on locked bodies.
- Free bodies do not collide with each other.

### 4.3 Lock rule and support rule

- A free body can lock into an empty gap cell that touches the cell where the body is.
- A bank cell that touches the gap has support 8.
- A locked body takes the highest support of the cells that it touches. Then it subtracts its cost.
- The cost is 1.0 when the body is alone in its row. The cost is 0.5 when a locked body is beside it in the same row.
- A body can lock only if its support will be more than 0.
- Calculate the support of all locked bodies again after each change.
- A locked body with support 0 or less falls. A body that falls goes out of the world.
- The result: a bridge one cell wide stops at 7 rows. A bridge two cells wide can cross the 12 rows.
- These numbers are a start. Keep them in one config file.

### 4.4 Player

- Touch controls: a stick below the left thumb moves the body. There are two buttons: Lock and Scent.
- Key controls: the arrow keys or W, A, S, D move the body. Space locks. Shift puts scent.
- The camera looks down at an angle and follows the body.
- Show clearly the cells where a lock is possible.
- One second after a lock, give the player a new body at the nest.
- A locked body of a player does not let go. It can fall.
- A locked body keeps the name of its player and the time of the lock. Show them when a player taps the body.
- Do not make accounts. Give each browser a random name. Keep the name in local storage.
- More than one player can be in the same world.

### 4.5 Scent

- While a player holds Scent, the cell below the body gets scent 100.
- A worker that carries food adds 20 to each cell on its way, to a maximum of 100.
- Scent decreases by 1 each second.
- Show scent on the ground.

### 4.6 Worker rules

1. **Go out.** Go to the cell that has the most scent and is farther from the nest. On a bridge, go to the far bank. With no scent near, move at random, not more than 6 cells from scent or from the nest.
2. **Lock.** At a gap or on a bridge: if a body can lock in the next row at the end of the bridge, go there and lock. If not, lock beside the first body on the way that is alone in its row.
3. **Carry.** If food is not more than 6 cells away, go to it and take one unit. Then go to the nest by the shortest way. Add 1 to the food count of the nest.
4. **Let go.** A locked worker lets go when no free body went on it, or on a body that it touches, for 20 seconds. It becomes a free worker again.

- A worker that falls starts again at the nest. The number of workers stays the same.
- The default is 200 workers. The number is a config value.
- Food and bodies have no cost in this plan. The food count is only a goal.

### 4.7 Save

- Save the world to one file each 30 seconds and at shutdown. Save the seed, the locked bodies with names and times, the scent and the food.
- Load the file at start.
- `mix colony.reset` deletes the file.

### 4.8 Look and size

- Make each body from code: three ellipsoids and six legs. The legs move when the body walks.
- Draw all bodies with instancing.
- Give each player a color from the name. Workers have one plain color.
- Use no model, image, sound or font files.
- The first load must be 500 KB or less after compression.
- The target on a phone is 30 frames each second with 1,000 bodies.
- `?stats=1` shows frames each second, the number of bodies, the delay to the server and the bytes each second.
- `?demo=1` runs with no input. Scent goes from the nest to the gap. Workers build the bridge and carry food. The camera moves slowly. This mode must look good in a video of 30 seconds.

## 5. Tests that you must do

Do each test yourself. Find the bugs before I do.

### 5.1 Automatic tests

Run the world with no browser. `mix test` must show these results:

1. A bridge one cell wide stops at 7 rows. A bridge two cells wide crosses 12 rows.
2. When a body falls, the bodies that lose their support fall also.
3. With 200 workers and scent from the nest to the gap, the workers complete a bridge and bring food in less than 5 minutes of world time.
4. When the scent goes away, all locked workers let go. Locked bodies of players stay if they have support.
5. Save and load give the same world.

### 5.2 Load test

`mix colony.load` runs 1,000 workers and 20 clients for 5 minutes at 10 ticks each second. Record the tick time (median, 95th and 99th percentile), the memory, and the bytes each second for each client.

- Target: the 95th percentile of the tick time is 50 ms or less.
- Target: each client gets 30 KB each second or less.

### 5.3 Play test

Play in a real browser as a new player does. Use real touch events at 390 x 844. Use real key events at a desktop size.

1. With 0 workers, cross the gap alone and touch the food. Record the time. The target is less than 4 minutes.
2. With 200 workers, put scent from the nest to the gap. Do not lock. Record the time to the first unit of food at the nest.
3. Open two browsers in one world. They must show the same bridge and the same names.
4. Load the page again. The world must be the same.
5. Start the server again. The locked bodies of players must be there with their names.

Write the report in `docs/playtests/0001-first-prototype.md`. Include screenshots, the numbers, the bugs that you found and repaired, and each thing that can confuse a new player. If a target is not met, say so.

You cannot measure the frame rate of a real phone. I will measure it with `?stats=1`.

## 6. Rules for this repo

- Write all text in ASD-STE100 Simplified Technical English: documents, code comments, names, log text and commit messages.
- Write documents in the first person, as I write them.
- Add no notes about the tools that helped to write the code or the text.
- Make `README.md`. It tells what the prototype is, how to start it and how to test it.
- Make `CONTRIBUTING.md` with these rules.
- Put this plan in `docs/plans/`.
- Work on the branch `feat/0001-first-prototype`. Do not open a pull request.
- If this plan does not decide something, select the simplest option. Record it in `docs/decisions.md`. Then continue.
- The rules in 4.3 and 4.6 are a start. If a test shows a problem, change the rule and record the change.
- Stop and ask me only in two cases: a target cannot be met after real work, or a change is necessary in section 1.

## 7. Not in this plan

- A cost for bodies, enemies, floods, towers, rafts, and more than one colony.
- Accounts, chat and moderation.
- Hosting and the WebAssembly target.
- A world that grows.
- Art work that the demo mode does not need.

## 8. Done when

- `mix phx.server` starts the game.
- All tests in section 5 are done and the report is in the repo.
- I can open the page on my phone, lock my first body in less than 60 seconds with no instructions, and cross the gap.
