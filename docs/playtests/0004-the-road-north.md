# Play test 0004: The road north

This is the report of the tests of [plan 0004](../plans/0004-the-road-north.md), section 5.
The decisions that the plan does not make are items 165 to 203 of
[`docs/decisions.md`](../decisions.md).

## Summary

| Target | Result |
|---|---|
| `mix test` shows the results of section 5.1 | **Met.** 116 tests and the slow test of the table, all pass. |
| The TLA+ contracts have the new rules, and `mix colony.contracts` is correct | **Met.** 8 models, 3,262 states, all rules hold. |
| Load test: tick time, 95th percentile, 50 ms or less (20 rivers, 150 carriers, 200 spare bodies, 2,000 locked bodies, 20 clients, 8 helpers) | **Met.** 2.91 ms. |
| Load test: each client gets 30 KB each second or less | **Met.** 4,991 bytes at the most. |
| 1. Slow player: the first food in less than 60 seconds | **Met.** 23 to 29 s, 3 seeds. |
| 1. Slow player: river 5 in less than 12 minutes | **Met.** 350 to 363 s. |
| 1. Slow player: never more than 20 seconds with no guide and no bright button | **Met.** 2.4 s at the most. |
| 1. Slow player: 60 spare bodies or fewer at the crossings of rivers 2 to 5 | **Met** with the factor 1.2: 37 at the most. With 1.5: not met (87). |
| 2. Fast players: 20 not slower than 5, 5 not slower than 1, to river 4 | **Met.** 46 to 52 s, 73 to 110 s, 124 to 181 s. |
| 2. Fast players: rivers in 10 minutes, 20 cross as many as 5 or more, 5 as many as 1 or more | **Met.** 19 to 20, 12 to 15, 7 to 8. |
| 2. Fast players: each client locks; with 5 and 20 each client carries food | **Met.** |
| 2. Fast players: no client has more than 20 seconds with no guide and no bright button | **Met.** 0.6 s at the most. |
| 3. The dead screen: always a guide or a bright button | **Not met.** 8.7 to 9.4 s with nothing, before the first crossing. The rule fails: see test 3. |
| 4. My bodies: the new name on all 5 bodies after the load, the panel | **Met.** 3 seeds. |
| 5. Two browsers: the same records, story and marks | **Met.** |
| 6. A long world: the frame time does not increase | **Met** for the length of the world: 27.6 ms and 32.3 ms with the same picture. With the bodies: 28.4 ms and 72.4 ms, because the long world has 350 bodies near the camera. See test 6. |
| 6. A long world: the first messages, the picture | 90 KB snapshot and 48 KB of records; the picture is 5.4 MB. |
| 7. The session: `main` changed, the workflow ran 5 minutes | **Met.** Run 46068813617, "success". |
| The picture of the story shows each name fully | **Met.** One column when a name and its numbers do not fit in two. |
| The save file has a new version; an older file gets a new name | **Met.** Version 5. |

The number that I changed: **the factor of the size of a pile is 1.2**, not 1.5
(section 4.3).

The fault that I did not repair: **a body takes food when it walks across a pile on the
way to the mark**, and then it cannot lock. See "Things that can confuse a player",
item 1. The plan does not let me change this rule.

## What these tests do not show

Read this first.

- **A script played, not a person.** The script is exactly the script of section 5.3. A
  new person looks around, stops, and does not walk in a straight line. No test tells if
  a lock feels good, if the sound is good, or if the game is fun: items 1, 2, 3 and 5 of
  section 8 need you.
- **The script walks in a straight line to the mark.** A person sees a pile on the way and
  can go around it. The script does not. See "Things that can confuse a player", item 1.
- **No real phone.** The test machine has no graphics card: Chromium draws with software,
  at 25 to 120 ms for each frame. The frame times of test 6 compare a young world and a
  long world on the same machine. They do not tell the frame time on your phone.
- **The fast clients have no browser.** They use the code of the page for the world, the
  guide and the button, and the same script.
- **The session ran with no player.** The workflow started, the tunnel gave an address,
  the address answered on the runner, and the artifact was there. Nobody opened the
  address on a phone.
- **Most tests ran two at a time** on one machine with 4 cores: the fast clients of test 2
  and the browser tests 1, 3, 4 and 5. The times of the game do not depend on the speed of
  the machine, but a slow frame can make the script a little later. Test 6 and the load
  test ran alone.
- **Nobody heard the sound.** The test machine has no speaker.

## 5.1 Automatic tests

`mix test`: 116 tests pass, in about 200 seconds. `mix test --only slow` (the table with
200 runs) passes, in about 130 seconds.

| # | Result of the plan | Result |
|---|---|---|
| 1 | Twenty bodies lock as fast as the rules permit for 5 minutes; the carriers never decrease; food comes all the time while a pile has food | **Met.** 20 helpers that never wait: 671 locks and 11 crossings in 5 minutes of world time. The carriers go from 12 to 100 and never decrease. The longest time with no new food is 21.1 s, after the crossing of a river 27 rows wide: shorter than one trip to the farthest pile with food. |
| 2 | The nest moves at each crossing; the carriers and the spare bodies get to the new place; a player with food can bring it to the new nest | **Met.** |
| 3 | The sizes and the least units of the piles, from the table | **Met.** Pile 1: 114 units, 88 at the least. Pile 6 and after: 600, 517 at the least. |
| 4 | With no player, the world does not change in 10 minutes; with a page that only looks, the same | **Met.** The server makes no tick. It saves the world when the last player goes. |
| 5 | The order of the guide rules, and "share the work" | **Met.** The guide of the page and the guide of the server give the same target in 225 cases: 75 places of a body, each with no food, after a lock, and with food. 36 cases give the nest, 36 an open cell, 36 a pile, and 117 no target (a body on a land with no way to the colony). |
| 6 | A player with food cannot lock | **Met.** The lock gets "error", and the colony keeps its spare body. |
| 7 | 20 seeds, 20 rivers: the widths, no way around, a pile and a start of a bridge for each river | **Met.** For each seed, each river has the widths of its row of the table (the largest is 27), each land is closed, and each pile is on its land with 13 start cells for its bridge. |
| 8 | The table for each width from 5 to 27: no run stops | **Met.** 200 random runs and the best run for each width. No run stops, and the highest of the runs is the number of the config. See below. |
| 9 | A new name changes all the bodies; a second join with the same secret number is the same player | **Met.** The new name goes to the bodies, the records and the story. Another number, or no number, is a new person. The server keeps only the SHA-256 of the number. |
| 10 | Save and load keep the nest, the old nests, the two kinds of workers, the players and their numbers | **Met.** A join with the same number after the load gets the same bodies, food and walks. |
| 11 | The contracts | **Met.** See "TLA+ contracts". |

## 5.2 Load test

`mix colony.load`: a long world, then 20 clients and 8 helpers for 5 minutes. The task
makes the world first with fast locks into random open cells, until the colony crossed
20 rivers and has 2,000 locked bodies: then it had 25 crossings (decision 199). The server
then loads this world with 150 carriers and 200 spare bodies.

| | Result | Target |
|---|---|---|
| The world | 28 rivers in the grid, 25 crossings, 2,000 locked bodies, 150 carriers, 200 spare bodies | 20 rivers, 2,000 locked bodies, 150 carriers, 200 spare bodies |
| Ticks of the server | 3,000 in 300 s: 10.0 each second | 10 |
| Tick time, median | 1.26 ms | |
| Tick time, 95th percentile | **2.91 ms** | **Met**: 50 ms or less |
| Tick time, 99th percentile | 17.62 ms | |
| Tick time, maximum | 269 ms | |
| Memory of the VM, maximum | 232 MB | |
| Memory of the world process | 112 MB | |
| Bytes each second for each client | **4,991** at the most | **Met**: 30,000 or less |
| Ticks each second that a client got | 10.0 | |

In the 5 minutes, the 8 helpers made 2 more crossings with 131 bodies. The longest tick
(269 ms) is a crossing: the grid grows, and the server makes the maps of the ways of the
long world again. A crossing comes one time in some minutes. The world process has 112 MB:
most of it is the maps of the ways to the nest and to each pile with food, one entry for
each cell that a body can get to.

### The table of the bridges

`mix colony.table --runs 200` and `test/open_test.exs` build a bridge on a river with one
width, with the rule of the server. "Random" is the highest of 200 runs that take a
random open cell. The config has these numbers.

| Width | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Best (B) | 5 | 6 | 7 | 8 | 10 | 13 | 16 | 19 | 22 | 25 | 28 | 31 | 36 | 41 | 46 | 51 | 56 | 61 | 66 | 73 | 80 | 87 | 94 |
| Random (R) | 5 | 6 | 7 | 8 | 10 | 13 | 19 | 23 | 28 | 34 | 39 | 43 | 48 | 54 | 58 | 64 | 69 | 74 | 80 | 85 | 89 | 94 | 100 |

The piles from these numbers, with 5 units for each body, 1.2 and 1.1:

| Pile | 1 | 2 | 3 | 4 | 5 | 6 and after |
|---|---|---|---|---|---|---|
| Size | 114 | 204 | 324 | 414 | 510 | 600 |
| Least units | 88 | 138 | 226 | 308 | 402 | 517 |

## 5.3 Play tests

`node test/play/run.mjs` does the browser tests in Chromium at 390 x 844 with real touch
events. `node test/play/fast.mjs` does test 2. Each test uses the seeds 2027, 11 and 42,
and a new world for each seed. The pictures are in [`0004/`](0004/).

### 1. One slow player, 15 minutes

| Target | Seed 2027 | Seed 11 | Seed 42 | Result |
|---|---|---|---|---|
| The first food at the nest in less than 60 s | 26 s | 23 s | 29 s | **Met** |
| River 5 crossed in less than 12 minutes | 362 s | 350 s | 363 s | **Met** |
| Never more than 20 s with no guide and no bright button | 2.4 s | 2.4 s | 0.6 s | **Met** |
| 60 spare bodies or fewer at the crossings of rivers 2 to 5 | 5, 15, 20, 23 | 10, 12, 37, 35 | 5, 18, 20, 24 | **Met** |

In 15 minutes the slow player crossed 6, 7 and 6 rivers, with 310, 330 and 318 locks.

The first run, with the factor 1.5 of the plan, did not meet the last target: 70 and 87
spare bodies at the crossing of river 5 (seeds 2027 and 11). I changed the factor to 1.2
(decision 165). The other targets were met with 1.5 also.

### 2. One, 5 and 20 fast players, 10 minutes, no browser

| | 1 player | 5 players | 20 players |
|---|---|---|---|
| Time to the crossing of river 4 (seeds 2027, 11, 42) | 128, 124, 181 s | 73, 108, 110 s | 52, 46, 52 s |
| Rivers crossed in 10 minutes | 7, 8, 8 | 15, 14, 12 | 19, 19, 20 |
| Clients with no lock | 0 | 0 | 0 |
| Clients that never carried food | 1 of 3 runs | 0 | 0 |
| The longest time with no guide and no bright button | 0 s | 0 s | 0.6 s |

| Target | Result |
|---|---|
| River 4: 20 players are not slower than 5, and 5 are not slower than 1 | **Met** for each seed. |
| Rivers in 10 minutes: 20 players cross as many as 5 or more, 5 as many as 1 or more | **Met** for each seed. |
| Each client makes one lock or more | **Met.** |
| With 5 and with 20, each client carries food one time or more | **Met.** The fewest trips of one client: 7 (5 players) and 4 (20 players). |
| No client has more than 20 s with no guide and no bright button | **Met.** 0.6 s at the most. |

The locks and the food of each client (units of food that the client carried to the
nest):

| Run | Locks of each client | Food of each client |
|---|---|---|
| 1 player, seed 2027 | 359 | 90 |
| 1 player, seed 11 | 433 | 0 |
| 1 player, seed 42 | 409 | 90 |
| 5 players, seed 2027 | 222, 212, 180, 194, 196 | 90, 90, 104, 100, 90 |
| 5 players, seed 11 | 207, 199, 178, 183, 180 | 90, 70, 70, 80, 110 |
| 5 players, seed 42 | 178, 175, 158, 150, 146 | 124, 137, 150, 140, 130 |
| 20 players, seed 2027 | 88, 85, 75, 74, 76, 77, 80, 67, 74, 65, 64, 73, 68, 72, 62, 60, 62, 61, 66, 70 | 140, 110, 130, 120, 120, 120, 120, 131, 100, 132, 120, 100, 110, 100, 110, 110, 110, 120, 110, 106 |
| 20 players, seed 11 | 81, 73, 78, 77, 64, 88, 65, 83, 79, 75, 86, 74, 69, 61, 84, 49, 50, 78, 54, 71 | 110, 146, 130, 120, 150, 100, 150, 110, 100, 130, 80, 90, 130, 130, 90, 160, 130, 61, 120, 120 |
| 20 players, seed 42 | 91, 80, 77, 82, 73, 77, 79, 73, 74, 69, 67, 75, 72, 71, 70, 72, 71, 72, 74, 66 | 40, 70, 60, 50, 60, 60, 60, 70, 60, 60, 60, 60, 53, 60, 60, 50, 43, 40, 50, 60 |

A player alone carries food when the colony has no spare body (rule 3), or by accident:
see "Things that can confuse a player", item 1.

### 3. The dead screen

4 carriers, 3 spare bodies and one fast player for 3 minutes.

| Target | Seed 2027 | Seed 11 | Seed 42 | Result |
|---|---|---|---|---|
| The player always has a guide or a bright button | 9.4 s with none | 8.7 s with none | 8.7 s with none | **Not met** |

**Why the rule fails.** Each time with nothing to do is before the first crossing. I
checked it with the same script and no browser: two times of 6 s and of 9 to 10 s, at
stage 1, with 0 spare bodies and no pile that a body can walk to. The 3 spare bodies make
3 locks. River 1 needs 5 to 7. The carriers cannot get food: pile 1 is across river 1.
Thus only the slow help of section 4.1 makes spare bodies: one each 10 seconds. In these
10 seconds no rule of the guide applies, and the button shows the body sign with 0. After
the first crossing, the player always had a target.

None of the four numbers of section 4.3 changes this: the time comes from the slow help
(10 seconds) and from the spare bodies at the start. I did not change them, because the
plan does not let me. Two changes that would meet the target: the slow help makes a spare
body each 2 seconds while the colony has none, or rule 4 shows the nest, where the next
spare body comes out.

### 4. My bodies

| Target | Seed 2027 | Seed 11 | Seed 42 | Result |
|---|---|---|---|---|
| After the load, all 5 bodies have the new name | 5 of 5 | 5 of 5 | 5 of 5 | **Met** |
| The panel shows 5 bodies and the walks | 5 bodies, 145 walks | 5 bodies, 179 walks | 5 bodies, 29 walks | **Met** |

The script locks 5 bodies, taps its name, taps the button for a new name, and loads the
page again in the same browser. The page joins with the same secret number. The panel is
in [`0004/name-panel.jpg`](0004/name-panel.jpg).

### 5. Two browsers

| Target | Result |
|---|---|
| The same records | **Met.** Two records with the names of the two players. |
| The same story | **Met.** 22 locks and 2 names, the same order, bodies and food. |
| The same marks of the open cells | **Met.** The same open cells, gains and bright cells in 170 of 177 looks. |

A look can fall between two messages: one page has the new open cells, the other not yet.
The walks of each player in the two stories were different by 7 and 5 (602 and 609, 423
and 428): the workers walk all the time, and the two pages ask for the story at two
moments. The first run of this test compared the walks also, and it reported "not met"
for this reason. The test now compares the story without the walks.

### 6. A long world

20 fast clients with no browser played for 20 minutes in a new world (seed 2027). Then a
browser opened the game and the story.

| | The young world | The long world |
|---|---|---|
| Crossings, rivers in the grid, rows | 0, 3, 70 | 35, 38, 1,277 |
| Locked bodies | 0 | 2,910 |
| Parts of the world that the page drew | 2 of 3 | 3 of 54 |
| Frame time with no body drawn (median, 90th percentile) | 27.6 ms, 36.0 ms | 32.3 ms, 38.3 ms |
| Bodies drawn | 14 | 350 |
| Frame time with the bodies (median, 90th percentile) | 28.4 ms, 36.0 ms | 72.4 ms, 83.9 ms |

| Target | Result |
|---|---|
| The page draws only the lands near the camera | **Met.** 3 parts of 54. |
| The frame time does not increase when the world is 20 rivers long | **Met** for the length of the world: 27.6 ms and 32.3 ms with the same picture (no body). The long world has a third part in the picture at the place of its nest. |
| A position in a message is correct in a world of 1,000 rows or more | **Met.** The world has 1,277 rows. The protocol test checks a world of 32 rivers. |
| The story takes 40 seconds at the most | **Met.** 2,910 bodies in 40 s. |

**The frame time with the bodies is larger in the long world**: 72.4 ms with 350 bodies
near the camera, and 28.4 ms with 14. This is not the length of the world. The long world
has 150 carriers and 200 spare bodies at the nest (the limits), and the young world has 22
workers. A short world with 350 workers is as slow: with 150 carriers and 200 spare bodies
at the start, the young world took 74.7 ms (with 262 bodies drawn) in my first measure.
The test machine draws with software: a phone with a graphics card is much faster, but
350 bodies are also more work for it.

The script of the page took 0.8 ms for each frame in the young world and 1.5 ms in the
long world (CDP metrics): the rest of the frame time is the drawing.

The first run of this test compared the frame time with the bodies, and reported "not
met" for this reason (29.2 ms and 64.1 ms). I changed the test to compare the same picture
(decision 201).

**The first messages and the picture:**

| | Size |
|---|---|
| The snapshot (the first message of the world) | 90,312 bytes |
| The records of the 35 bridges | 47,849 bytes |
| All the messages of the first 10 seconds | 148,069 bytes in 54 messages |
| The picture of the story | 5,376,900 bytes: 8 parts of the screen, 390 x 7,268 pixels with the names, 20 names |

The end of the story in a long world is a thin strip: the full world fits above the list
of the names ([`story-long-world.jpg`](0004/story-long-world.jpg)). The picture that the
button saves is taller and shows the world with the full width.

### 7. The session

| Target | Result |
|---|---|
| The default of the input `branch` on `main` is `feat/0004-the-road-north`, in a commit with only this change | **Met.** Commit 11e5e03 on `main`: one line of `.github/workflows/play-session.yml`. |
| Start the workflow one time for 5 minutes | **Met.** Run 46068813617, "success", 6 minutes 30 seconds. |

The log of the run: the server started with the branch `feat/0004-the-road-north` (commit
a32e39a, part 3), the tunnel gave an address and the address answered, the time ran out
after 5 minutes, and the artifact was saved (1,310 bytes). Nobody joined: the world did
not tick (section 4.4), and its file has no lock. The workflow still gives the input
`workers` to the script: the script does not use it now (decision 196).

### The screenshots

| Picture | What it shows |
|---|---|
| [`workers.jpg`](0004/workers.jpg) | The two kinds of workers at the nest: the small dark carriers and the red brown spare bodies. |
| [`nest-move.jpg`](0004/nest-move.jpg) | The new nest at the foot of the new bridge, some seconds after the crossing. The carriers bring white eggs. |
| [`button-food.jpg`](0004/button-food.jpg), [`button-none.jpg`](0004/button-none.jpg), [`button-rest.jpg`](0004/button-rest.jpg), [`button-lock.jpg`](0004/button-lock.jpg), [`button-dim.jpg`](0004/button-dim.jpg) | The 5 states of the button. |
| [`guide-open.jpg`](0004/guide-open.jpg), [`guide-nest.jpg`](0004/guide-nest.jpg), [`guide-pile.jpg`](0004/guide-pile.jpg) | The mark of the guide on an open cell, on the nest and on a pile. |
| [`wider.jpg`](0004/wider.jpg) | The "wider" phase: bright cells and weak cells. |
| [`name-panel.jpg`](0004/name-panel.jpg) | The panel of my name. |
| [`lands-5-to-8.jpg`](0004/lands-5-to-8.jpg) | Lands 5 to 8 from above: spring, summer, autumn and winter again. |
| [`story-10-rivers-play.jpg`](0004/story-10-rivers-play.jpg), [`story-10-rivers.jpg`](0004/story-10-rivers.jpg) | The story of a world with 10 crossings: while it plays, and at its end. |
| [`story-long-world.jpg`](0004/story-long-world.jpg) | The end of the story of the world of test 6. |

The button "wait" has no picture. It shows only when no rule of the guide applies and
the colony has a spare body. In the tests this was only in the first frames of the page.
With no spare body, the button shows the body sign with 0 (decision 182).

The worlds of `lands-5-to-8.jpg` and of the story of 10 rivers come from
`test/play/make_long.exs`: a script that makes the locks of 6 players fast, with no walk.

## TLA+ contracts

`mix colony.contracts` checks 8 models in 2 minutes and 19 seconds. All the rules hold.

| Model | States | What it checks |
|---|---|---|
| `Bridge` | 147 | The support rule in all the structures of a river 3 cells wide. |
| `BridgeWide` | 711 | The same with lines of 4 bodies. |
| `BridgeOpen` | 29 | The open cells. |
| `BridgeOneWide` | 8 | One body wide stops at 7 rows. |
| `BridgeTwoWide` | 3 | Two bodies wide stops at 15 rows. |
| `BridgeThreeWide` | 4 | Three bodies wide stops at 23 rows. |
| `BridgeNineRows` | 632 | Each bridge across 9 rows has 10 bodies. |
| `Colony` | 1,728 | A player and the world with the rules of plan 0004: a lock uses a spare body and never a carrier, the carriers never decrease, a player with food cannot lock, the nest moves only at a crossing. |

The tests also follow the real world against `Colony.tla`: 4 runs of random messages of
two players with a helper, up to the first crossing. The contract has one river: after
the crossing, the world gets the next river, and the contract does not have it.

## Faults that I found and repaired

1. **The page sent moves of 5 bytes**, and the server read 7: the server refused all the
   moves and all the locks of the page. The first browser test found it.
2. **The mark of the guide was on the leftmost open cell.** Many open cells had the same
   number of steps. The guide now takes the cell nearest in a straight line, then the
   lowest cell number, on the page and on the server.
3. **The guide of the server was different from the guide of the page** for a body with
   no way to the nest. Now the nest rule needs a way on foot, on both.
4. **The spare bodies stood in one line** behind the first body at the crossing place.
   Now they spread to the free cells beside them (decision 170).
5. **Two saves at one time failed.** The save when the last player goes and the save at
   the stop used the same temporary file (decision 178).
6. **The demo page showed land 0** of a long world. Now it shows the nest and the next
   river.
7. **The end of the story hid the south part of a long world** behind the list of the
   names. Now the world is above the list.
8. **The numbers of the names in the picture ran into the second column** when the food
   numbers were large. Now the names are in one column then. Each name shows fully: the
   fault "Steady Berry 18" as "Steady Berry 1" is gone.
9. **The way to the crossing place covered all the world** at each lock. In a long world
   this made a lock slow. Now the map goes 30 steps past the nest (decision 171).

## Things that can confuse a player

1. **The body takes food on the way to the mark.** The pile of the land is often on the
   straight line from the end of the new bridge to the open cells of the next river. The
   way of the guide goes around the pile, but the script, as a person, walks straight to
   the mark when it is on the screen. The body takes 10 units, cannot lock, and the guide
   sends it back across the bridge to the nest. With one fast player and seed 2027 (and
   the factor 1.5), I logged it: 11 times in a row after the crossing of river 5, and the
   next river took 4 minutes, not 2. The slow player of test 1 needed 315 s for river 6
   with seed 2027; I did not check if the cause is the same. The same fault was in plan
   0003 (fault 5 of its report): the repair then was the way of the
   arrow, but the arrow does not show when the mark is on the screen. Possible repairs:
   a body takes food only when its guide shows the pile, or the next pile is not between
   the bridge and the open cells.
2. **The first seconds have nothing to do** when the colony has few spare bodies at the
   start: see test 3. The button shows the body sign with 0, and no mark shows where to go.
3. **A pile on the land of the nest stays.** A carrier goes to the pile nearest to the
   carrier. After a crossing, some carriers walk to an old pile far behind, and the food
   comes late (automatic test 1).
4. **The old nests look like the nest.** An old nest is a low ring with an empty hole and
   a number. On a phone the difference is small.
5. **A tap on my name now opens a panel.** Before, it gave a new name at once. A player
   who knows the old game can think that the name button does not work.
6. **All the open cells are bright while the bridge goes forward.** Only in the "wider"
   phase are some cells weak. A player can think that the weak cells are not open.
7. **The picture of a long world is a large file**: 5.6 MB for 10 crossings, 780 x 4,670
   pixels. Some messengers make it smaller or refuse it.
8. **The story of a long world goes fast.** 0.25 s for each body and 40 s at the most:
   with 2,910 bodies, 73 bodies appear each second.
9. **The end of the story of a long world is a thin strip.** The full world fits on the
   screen, thus each land is a thin line, and the bridges do not show. The saved picture
   is the view with detail.
10. **The numbers of the old nests** show in the world, one for each crossing. In the
    story they do not show: in the view from above they were on top of each other.

## Numbers that I changed

- **The factor of the size of a pile: 1.2, not 1.5** (section 4.3, decision 165). With
  1.5, the slow player had more than 60 spare bodies at the crossing of river 5.

## What this version tells me about section 8

1. **Alone for 10 minutes:** the slow script crossed river 5 after about 6 minutes, and
   the fast script crossed 7 or 8 rivers in 10 minutes. The slow script never had more
   than 2.4 s with nothing to do. You can only have a time with nothing to do before the
   first crossing (test 3), and with a body that took food by accident.
2. **With other persons:** 5 fast players crossed 12 to 15 rivers in 10 minutes, and 20
   crossed 19 or 20. Alone: 7 or 8. Each player locked and carried food.
3. **With no spare body:** after the first crossing, the guide shows a pile and then the
   nest, and the button shows the body sign with 0. Before the first crossing, nothing
   shows what to do for up to 10 seconds.
4. **A new name:** the 5 bodies of the test had the new name after the load, in 3 seeds.
5. **The feel and the sound:** the tests cannot tell. They need you.

