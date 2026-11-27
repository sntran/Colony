# Plan 0003: The crossing

Read `docs/plans/0001-first-prototype.md`, `docs/plans/0002-players-are-the-bridge.md` and `docs/decisions.md` first. This plan changes the rules of plan 0002. Where this plan says nothing, plan 0002 stays.

## 1. What the second prototype showed

All the checks of the report of plan 0002 gave the same results on a second machine: 83 tests, 6 contracts, the load test and the play scripts. The work was correct. The rules of the plan were not good. A play test at phone size showed this:

- **No Scent, no food.** A player made a correct bridge of 6 bodies in 16 seconds and did not hold Scent. No food came in 90 seconds, and the pile lost 100 units. Then the player held Scent from the nest to the pile one time. Food came 8 seconds later. Nothing on the screen tells a player this.
- **The 17.5 seconds of the report are not the time of a new player.** The play script held Scent from the first second and went to the narrowest column. The plan said only: push forward and tap Lock when the button is bright.
- **A player who taps Lock each time it is bright stops the colony.** 34 bodies, a bridge 10 bodies wide at the bank, all 30 workers used in 67 seconds, no food after 150 seconds. Each lock uses one worker, and nothing shows that.
- **After the first bridge, no bridge is necessary.** The second pile was across 9 rows. Food came with no new body: a walk along the far bank with Scent was sufficient. A pile that nobody locks for loses nothing, thus there was no hurry.
- **`?demo=1` puts 4 helpers into the world of a play session.** The summary of the session gives this address to all the players.

## 2. The goal

The first ten minutes of the game must have the quality of a finished game.

1. A person who knows nothing gets the first food in less than 60 seconds, with one thumb on the stick and one thumb on one button, and with no words on the screen.
2. Each lock feels good: the person sees it, hears it, and knows immediately where the new body is.
3. The game has a start, harder and harder work, and an end. At the end, the persons see the story of their colony with their names, and they can keep it.

The questions of plan 0002 stay: is it fun alone, do 5 to 20 persons build together with no chat, and does a person want to see the record.

## 3. New words

| Word | Meaning |
|---|---|
| Land | Ground where a body can walk. Land 0 has the nest. Lands 1 to 4 are after the rivers 1 to 4. |
| Spare body | A free worker. The number at the top of the screen counts the spare bodies. |
| Open cell | A river cell where a lock is possible and helps (4.5). |
| Crossing | The moment when a bridge touches the next land. |
| Story | All the locks of the world in the order of their times, with the names. |

## Part 1: The rules

Do part 1 first. Do the tests of part 1 (section 5). Start part 2 only when the targets of part 1 are met.

### 4.1 No button Scent. The workers smell the food.

- Remove the button Scent and the key Shift. A player does not put scent.
- A free worker obeys the first rule that applies:
  1. It carries food: go to the nest by the shortest way.
  2. A pile with food is there, and the worker can walk to it: go to the nearest such pile and take one unit. No scent is necessary.
  3. A pile is there, and no body can walk to it: go to the crossing place and wait there. The crossing place is the bridge to that land if a bridge is started, and the land behind that bridge. If no bridge is started, it is the edge of the land, in the column of the pile, 3 cells or less to each side.
  4. Move at random near the nest.
- If rules 2 and 3 apply at the same time, one worker of each three waits at the crossing place. The other two carry food.
- The workers that wait are the spare bodies of the builders. They move a little all the time and look to the pile.
- A worker with food puts scent, as before. Scent is now only a picture of the road. No rule reads it.
- A worker never locks.

### 4.2 The world: four rivers

- The world goes north from the nest: land 0, river 1, land 1, river 2, land 2, river 3, land 3, river 4, land 4. Each river goes across the full width of the world. There is no way around a river.
- The width of a river changes with the column, by 1 row or less from one column to the next.

| River | Width in rows | Bodies for a bridge (see 4.5) |
|---|---|---|
| 1 | 5 to 7 | 5 to 7 |
| 2 | 9 to 11 | 10 to 18 |
| 3 | 12 to 14 | 19 to 30 |
| 4 | 16 to 18 | 31 to 51 |

- The south edge of each river is a straight line of cells. The north edge is not straight. Each land after a river is 8 rows deep or more in each column. Land 0 is 14 rows deep. The world is 60 columns wide.
- A bridge gets support from the land on each side, as in plan 0002. The support rule does not change: 96 for the land, costs 12, 6, 4 and 3.
- Each land has its own colors (4.11).

### 4.3 The piles

- At the start, pile 1 is on land 1, 3 rows after the river, in a column 10 or less from the column of the nest.
- When a bridge touches land `k`, pile `k + 1` appears on land `k + 1`, in a random column that is 10 or more from each edge of the world. After land 4 there is no more pile.
- The sizes: 300, 400, 500 and 600 units.
- A pile that no body can walk to loses 1 unit each second, from the moment when it appears. It does not go below 50 units. The loss stops for always at the crossing.
- 5 units of food at the nest make one worker (`food_per_worker`). I start with 5. You can change this number to meet the target "no long wait" of section 5.3. Tell me the number.
- The colony starts with 30 workers. With fewer than 5 spare bodies, the nest makes one worker each 10 seconds, as before.

### 4.4 A lock uses one spare body

- A lock is possible only if the colony has one spare body or more. The body of the nearest spare body, by steps on foot, is the new body of the player, as in plan 0002.
- With no spare body, the button Lock is not bright, the number of spare bodies at the top flashes, and a low sound plays if the player taps Lock.
- Remove the rule "with no free worker, the player is at the nest after 3 seconds". A player always has a body, because a player locks only when a spare body is there.
- A player who joins gets a body at the nest. This body does not use a spare body.

### 4.5 A lock is possible only where it helps

A bridge to land `k` is the group of locked bodies in river `k` that touch each other.

- **One bridge for each river.** If river `k` has no body, a lock is possible in each cell of its first row that is 6 columns or less from the column of pile `k`. After the first lock, a lock is possible only in a cell that touches the bridge.
- **Forward first.** The top row is the highest row of the bridge. If a lock is possible (by the support rule) in a cell of the next row that touches the bridge, only these cells are open.
- **Wider only when the bridge cannot go forward.** If no such cell is there, a cell that touches the bridge is open if a body there makes the highest support of the top row larger.
- **A complete bridge takes no more bodies.** When a body of the bridge touches land `k`, the bridge is complete.
- The server and the page use the same rule. The page shows each open cell on the screen with a bright edge that moves slowly, all the time, not only near the player.
- The button Lock is bright if an open cell touches the cell of my body and the colony has a spare body. If two open cells touch my cell, the page takes the cell nearest to the direction of the stick.
- Two players can tap for the same cell. The first one gets it. The other one gets no error on the screen.

I tested this rule with the support rule of the page (`support.js`), on rivers with one width. "Best" always takes the open cell with the largest gain. "Random" takes a random open cell: this is a player who taps each time the button is bright. No run stopped before the far land.

| Width | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 16 | 17 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Best | 5 | 6 | 7 | 8 | 10 | 13 | 16 | 19 | 22 | 25 | 31 | 36 | 41 |
| Random, highest of 25 runs | 5 | 6 | 7 | 8 | 10 | 14 | 18 | 22 | 27 | 30 | 42 | 47 | 51 |

Make an automatic test that gives this table. If your numbers are different, tell me why.

### 4.6 A player can carry food

- A player whose body touches a pile with food takes 10 units, or all the units if fewer are there. The body shows the food.
- At the nest, the food goes into the nest, and the new workers come out immediately.
- A player who locks loses the food that the body carries.
- A record counts the food that each player carried.

### 4.7 The end

- The world is complete when the first food of pile 4 gets to the nest.
- Then each page shows the story (4.13) one time. After it, the players can walk and look. The server keeps the world.
- A new world starts only when I start the server with a new save file.

## Part 2: The feel

### 4.8 The moment of a lock

In this order, in less than half a second:

1. The body goes down into the cell in 0.15 seconds. Its legs go to the bodies and the land that it touches. A ring goes out on the water.
2. A note plays (4.10). The phone shakes for 15 milliseconds if the browser can do that.
3. A point of light, in the color of the player, flies from the locked body to the new body in 0.4 seconds. The camera follows the light. Thus the player always knows where the new body is.
4. The name label of the locked body shows for 2 seconds.

A player who pushes forward and taps must be able to lock one time each 1.5 seconds on river 1. Make this rhythm feel good.

### 4.9 The moment of a crossing

1. The camera moves back and shows the full bridge for 2.5 seconds. A move of the stick stops this.
2. The notes of the bridge play again, fast, in the order of the locks: the song of the bridge. Then one chord.
3. The workers that waited go across in a line. This is the best picture of the game. Make it look good.
4. The record card shows. Then the light of the next pile appears, and the arrow (4.12) points to it.

### 4.10 Sound, with no sound files

- Make each sound with the Web Audio API. Start the sound at the first touch. A small button with a sign stops and starts the sound.
- **Lock:** one note of a scale of five notes. A higher row is a higher note. Each river has its own key.
- **Crossing:** the song of the bridge, then a chord.
- **Water:** noise through a filter, louder near a river.
- **Steps:** very soft ticks for my body.
- **Food at the nest:** a small sound. A new worker: a different small sound.
- **No spare body:** a low sound.
- The sound must not hurt with 20 players: put a limit on the number of notes each second.

### 4.11 The look

- **The bridge lives.** A locked body goes down a little when a body walks on it, and comes back like a spring. A body with low support shakes, as before.
- **The water moves** in one direction. White foam is at the land and around each locked body.
- **Four lands, one year.** Land 0 and 1 are spring, land 2 is summer, land 3 is autumn, land 4 is winter. Change the colors of the ground, the grass and the light. No image files.
- **Shadows** below each body. Fog far away.
- **The crowd.** The workers that wait at a crossing place must look like they want to go across.
- **The camera** follows the body softly and looks a little in the direction of the move.
- **Speed.** The target is 60 frames each second on a phone that is 4 years old or newer. If a frame takes more than 20 milliseconds for 2 seconds, the page decreases the resolution. `?stats=1` shows the frame time. I measure on my phone.
- **Size.** The first load is 100 KB or less. No image, model, font or sound file.

### 4.12 The screen has no sentences

- Use signs, numbers and names only. Remove "You are at the food" and the other sentences. The button Lock has a sign of two bodies that hold each other, not a word.
- **One arrow** at the edge of the screen, when its target is not on the screen:
  - I can lock and the colony has a spare body: to the nearest open cell.
  - The colony has no spare body: to the nearest pile with food that I can walk to.
  - I carry food: to the nest.
- **The top of the screen:** the number of spare bodies and the food in the nest, with their signs. The number of spare bodies decreases by one at each lock, with a small move, and flashes at 0.
- **The pile** shows its number. The number is red while the pile loses units.
- **My name** stays the same on my device (local storage). A tap on my name gives a new random name.
- **The record card** has signs and numbers: the river, the names with the bodies and the food of each player, the food that was left in the pile at the crossing (for example 262 of 300), and the seconds.

### 4.13 The story

- A button with a sign opens the story. `/?story=1` opens it with no body in the world.
- The story shows all the locked bodies appear in the order of their times, in 20 to 40 seconds, from the nest to the north. Each lock plays its note. The first body of each player shows the name.
- At the end, the page shows the full world from above, with the road, the bridges and the list of the names with their bodies and their food.
- A button saves this picture as a PNG file, or opens the share function of the phone if the browser has it. The picture has the date and the names.
- The story works at each time, also before the world is complete.

## Part 3: The play session

### 4.14 Demo mode and helpers

- `?demo=1` adds no helper. It shows the story one time, then the live world with a slow camera.
- Helpers come only from `COLONY_HELPERS` or from the input of the workflow.
- A helper obeys the new rules: it goes to the nearest open cell and locks, one lock each `16 / n` seconds with `n` helpers. With no open cell or no spare body, it carries food.

### 4.15 The workflow on `main`

- Put the file `.github/workflows/play-session.yml` on `main`, in a commit that has only this file. Change nothing else on `main`.
- The workflow has a new input `branch`. The default is `feat/0003-the-crossing`. The step `checkout` gets this branch. Thus I can start a session from the page Actions of GitHub with no other step.
- If the branch has no `mix.exs`, the job stops with a clear message.
- The summary gives the address of the game and the address of the story. It does not give the address of the demo mode.
- After the push, start the workflow one time for 5 minutes and tell me the result. If you cannot start it, tell me the exact reason.

### 4.16 Other changes

- The save file has a new version. The server does not load a save file of plan 0002: it keeps that file with a new name and starts a new world.
- `mix colony.records` prints the records and the story.
- Change the TLA+ contracts to the new rules: a lock needs a spare body, a lock is possible only in an open cell, a complete bridge takes no more bodies, a worker never locks. `mix colony.contracts` must be correct.

## 5. Tests that you must do

Do each test yourself. Find the bugs before I do.

### 5.1 Automatic tests

1. With no player and no helper, no body locks in 5 minutes of world time, and the workers wait at the crossing place of river 1.
2. One body locks 6 times across river 1 and does nothing more. Food is at the nest in less than 20 seconds of world time after the crossing.
3. The table of section 4.5.
4. A lock in a cell that is not open gets the reply "error". A lock with no spare body gets the reply "error".
5. Two bodies that lock into the same cell in the same tick: one gets the cell.
6. No way around: for 40 seeds, no body can walk from land `k` to land `k + 1` with no bridge.
7. The piles: the place, the size, the loss, the limit of 50 units, and the next pile at the crossing.
8. A player carries 10 units to the nest, and the new workers are there.
9. Four helpers and no player complete the four crossings. Tell me the time.
10. The world is complete at the first food of pile 4. Save and load keep the lands, the bodies, the records and the story.
11. The contracts.

### 5.2 Load test

The targets of plan 0001, with 1,000 workers, 20 clients and 8 helpers, in the new world.

### 5.3 Play tests

Play in a real browser at 390 x 844 with real touch events.

**The new player.** The script for a new player knows only what a person sees. Use exactly this script:

- Each 0.1 seconds: if the button Lock is bright, tap it.
- If not: push the stick in a straight line to the nearest open cell on the screen. If no open cell is on the screen, push in the direction of the arrow.
- If the body did not move for 1 second, push to one side for 0.5 seconds, then to the other side.

The script does not read the grid, the rivers or the supports. **If a target fails with this script, do not make the script smarter.** Change a number of section 4 and tell me, or stop and tell me why the rule fails.

1. **A new player alone**, 30 workers, no helper. Targets:
   - The first food is at the nest in less than 60 seconds from the load.
   - The player completes the four crossings. Tell me the time of each crossing and the bodies of each bridge. The bodies are not more than the row "Random" of section 4.5 for the widest column of the bridge.
   - No long wait: the player never waits more than 20 seconds for a spare body.
2. **A player who never locks.** With 3 helpers. The player carries food 5 times. The record counts it.
3. **One player and 3 helpers.** The record has the names. Each lock of the player gives a new body 3 cells or less from the locked body.
4. **Two browsers.** The two players see the same record and the same story.
5. **Twenty new players.** 20 clients with the script of the new player, with no browser. They complete the four crossings. Tell me the time, and the locks and the food of each client. I want to know how many clients got no lock.
6. **The story.** `/?story=1` after test 1: all the bodies appear in order, and the PNG file has the names.
7. **Sound.** The page counts the notes that it plays. One note for each lock, and the song at each crossing. No error if the browser gives no sound.
8. **The session.** The result of section 4.15.

Make a screenshot of each moment of sections 4.8, 4.9 and 4.13, and of each land. Put them in `docs/playtests/0003/`.

## 6. Rules for the work

- Branch `feat/0003-the-crossing`, from `feat/0002-players-are-the-bridge`. No pull request.
- The only change on `main` is the workflow file of section 4.15.
- Commit part 1 with its tests before you start part 2.
- Write each decision that this plan does not make in `docs/decisions.md`, from item 113.
- Write the report in `docs/playtests/0003-the-crossing.md`. For each target, write "met" or "not met" first. Write what the tests do not show. Write each thing that can confuse a player.
- All the text obeys `CONTRIBUTING.md`.

## 7. Not in this plan

- A world with no end, and more than one colony.
- A limit on the number of bodies that can walk on a bridge at the same time, and wider bridges for more traffic.
- Bodies that fall, floods, enemies and weather.
- Accounts, chat, and names that a player types.
- An app for a phone store.

## 8. This plan is done when

1. I start a play session from my phone, from the page Actions of GitHub.
2. I open the address on my phone and get the first food in less than 60 seconds. I read no instructions.
3. I complete the four crossings alone and I never wait more than 20 seconds for a body.
4. I see the story with my name and I save the picture.
5. The game has sound, and each lock feels good to me.
6. Other persons open the address, and one bridge has the names of two persons or more.
