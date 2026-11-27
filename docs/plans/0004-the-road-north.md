# Plan 0004: The road north

Read `docs/plans/0003-the-crossing.md`, `docs/playtests/0003-the-crossing.md` and `docs/decisions.md` first. This plan changes the rules of plan 0003. Where this plan says nothing, plan 0003 stays.

## 1. What the third prototype showed

All the checks of the report gave the same results on a second machine: 99 tests, 8 contracts, the load test (2.0 ms and 4.4 KB each second on 2 cores), and the first load. The report was correct and complete.

These parts are good. Do not change how they feel: the moment of a lock, the camera at a crossing, the four seasons, the story with its picture, the screen with no sentences, the workflow of the play session.

A play test at phone size, on worlds with other seeds, showed these faults. The first four come from the rules of plan 0003, not from your work.

1. **More players are worse than one player.** One slow player (6 seconds to look, then 0.5 to 1.1 seconds before each tap) completed the world in 233 seconds. Five fast scripts crossed river 3 after 134 seconds and did not cross river 4 in 540 seconds. Your 20 clients needed 584 seconds. The cause: a lock uses a worker that carries food. Fast players use all the workers, no worker carries food, and the colony does not grow.
2. **With no spare body, the screen is dead.** With 9 workers and one fast player, the bridge of river 2 needed 125 seconds. The screen showed a red 0, no worker, and no arrow, because the pile was on the screen. Six times the script had nothing to follow for 5 seconds or more.
3. **One player alone has no pressure, and the game is short.** The slow player started with 30 spare bodies and had 97 at the end. The pile of river 1 had 276 of 300 units at the crossing. After 4 minutes there was no more work.
4. **A river of 30 rows cannot be crossed.** My test of the open cells with lines of 4 bodies: a bridge stops at row 28 with 112 bodies. At 27 rows, each run got across (94 bodies with "Best").
5. **While I carry food, the arrow shows the sign of an open cell.**
6. **A new name is a new person.** My old bodies keep the old name.
7. **Pile 1 loses units before the first player comes.**

## 2. The goal

1. More players always make the colony faster, not slower.
2. A player always has something to do, and the screen always shows what.
3. The world has no end. Ten minutes alone are full of work, and a group gets farther than one player.
4. My bodies are mine for always, also after a new name and after a new load of the page.

## 3. New words

| Word | Meaning |
|---|---|
| Carrier | A worker that carries food. A lock never uses a carrier. |
| Spare body | A worker that waits at the crossing place. A lock uses one spare body. A spare body does not carry food. |
| Foot of a bridge | The land at the south end of a bridge. |
| Guide | The one target that the page shows to a player at each moment (4.6). |

## Part 1: The colony

Do part 1 first, in the world of plan 0003 with its four rivers and its end. The tests of part 1 are the automatic tests 1 to 6 and the play tests 2, 3 and 5 of section 5. Commit part 1 with these tests before you start part 2. In part 1, the last pile has 600 units.

### 4.1 Two kinds of workers

- **Carriers.** The colony starts with 12. It gets 8 more at each crossing. A lock never uses a carrier. A carrier goes to the nearest pile with food that it can walk to, takes one unit, and brings it to the nest. With no such pile, it waits near the nest.
- **Spare bodies.** The colony starts with 10. All the spare bodies wait at the crossing place, as the workers that wait do now (decision 126). A lock uses the nearest spare body. The number at the top of the screen counts the spare bodies only.
- 5 units of food at the nest make one spare body (`food_per_body`). The new spare body comes out of the nest and walks to the crossing place.
- A person must see the difference in one look. A carrier is smaller and darker. A spare body is the size of the body of a player.
- Remove the rule "one worker of each three waits" and the rule "a new pile calls workers" (decision 128).
- The slow help of the nest stays, but only when it is necessary: with fewer than 5 spare bodies, and no pile with food that a body can walk to, the nest makes one spare body each 10 seconds.
- The limits: 150 carriers and 200 spare bodies.

### 4.2 The nest follows the colony

- At each crossing, the nest moves to the foot of the new bridge: 3 rows south of the first body of that bridge, or the nearest free land cell.
- Thus the food of pile `k` goes across bridge `k` to the nest, and each new bridge has a line of carriers on it. The new spare bodies go across the same bridge to the next crossing place.
- The carriers and the spare bodies walk to the new place. For some seconds, the carriers carry white eggs from the old nest to the new nest. This is a moment of the game: make it look good. The camera does not change.
- The old nest stays in the world as a mark with the number of its land.
- A player who joins starts at the nest. A player with food brings it to the nest.

### 4.3 A pile pays for the next bridge

- Pile `k` is on land `k`. Its food makes the spare bodies for the bridge across river `k + 1`.
- Use your table test of the open cells with 200 random runs. `B(k)` is "Best" and `R(k)` is the highest "Random" for the largest width of river `k`.
  - The size of pile `k` is `food_per_body × 1.5 × R(k + 1)`.
  - Pile `k` does not go below `food_per_body × 1.1 × B(k + 1)`.
- A pile loses 1 unit each second from the moment when it appears to the crossing, as before. Thus a slow bridge gives fewer bodies for the next bridge.
- Pile `k + 1` appears at the crossing of river `k`, in a column 12 or less from the column of pile `k`, and 10 or more from each edge.
- You can change these four numbers to meet the targets of section 5.3: the carriers at the start, the carriers for each crossing, `food_per_body`, and the 1.5. Tell me the numbers.

I made a rough calculation with these numbers. One slow player crosses 6 rivers in 15 minutes, never waits, and has 3 to 62 spare bodies at the crossings. Five and 20 fast players that carry food when the colony has no spare body cross 11 rivers or more. Five and 20 fast players that never carry food are as fast as one fast player, not slower.

### 4.4 The world stops when no player is there

- With no player in the world, the server makes no tick: no pile loses units, and no worker moves. A page that only looks (the story, the demo mode) is not a player.
- The server saves the world when the last player goes.

### 4.5 A player with food

- A player takes 10 units at a pile and brings them to the nest, as before. The new spare bodies come out immediately.
- A player who carries food cannot lock. Remove the rule "a player who locks loses the food".

### 4.6 One guide

The page always shows exactly one target to me. It takes the first rule that applies:

1. I carry food: the nest.
2. The colony has a spare body, and an open cell is there: the nearest open cell, by steps on foot.
3. A pile with food that I can walk to is there: the nearest such pile.
4. Nothing: no target. The button shows the sign "wait" (4.7).

- **Share the work.** If the colony has fewer spare bodies than players, and my last act was a lock, rule 3 comes before rule 2 for me. After I bring food, rule 2 comes first again. Thus in a group each player locks, then carries, then locks. A player alone always has rule 2 first.
- **The target has a mark on it**: a ring in my color that moves, also when the target is on the screen. When the target is not on the screen, the arrow at the edge shows the way on foot, with the sign of the target: an open cell, the nest, or food.
- With no spare body, the open cells have a weak grey edge.

### 4.7 The button tells why

The button shows the first state that applies:

| State | The button shows |
|---|---|
| I carry food | The food sign |
| The colony has no spare body | The body sign with 0, red, with a slow flash |
| My new body rests | A ring that fills in 1 second |
| A lock is possible | The lock sign, bright |
| My cell does not touch an open cell | The lock sign, not bright |

### 4.8 The open cells show how much they help

- In the "wider" phase, the server sends the gain of each open cell: how much the highest support of the top row increases.
- The cells with the largest gain are bright. The other open cells are weak. A lock is possible in each of them.
- The record card shows the bodies of the bridge and `B` for its widest column, for example "19 / 16". Thus a player sees that a bridge with fewer bodies is possible.

## Part 2: The world has no end

### 4.9 Rivers and lands

| River | Width in rows |
|---|---|
| 1 | 5 to 7 |
| 2 | 9 to 11 |
| 3 | 12 to 14 |
| 4 | 16 to 18 |
| 5 | 19 to 21 |
| 6 | 22 to 24 |
| 7 and each river after it | 25 to 27 |

- No river is wider than 27 rows (section 1, item 4). Make your table test for each width to 27. No run can stop before the far land.
- The server makes the world as far as two rivers after the newest pile. The save file keeps all the world.
- The seasons repeat: each four lands are one year.
- Remove "the world is complete" and the story that opens by itself. After each crossing, the story button flashes for some seconds.

### 4.10 A long world on the page and in the messages

- The page draws only the lands near the camera. The frame time must not increase when the world is 20 rivers long.
- A position in a message must be correct in a world of 1,000 rows or more.
- The list of the records moves with a finger.
- The picture of the story shows all the world. For a long world the picture is taller.
- The story takes 0.25 seconds for each body, 6 seconds at the least and 40 seconds at the most.

## Part 3: My bodies

### 4.11 A player is the same person for always

- The page makes a secret random number one time and keeps it in the local storage. The join message has this number and the name.
- The server knows a player by this number. A new name changes the name on all the bodies of that player, in the records and in the story.
- With no local storage, the game works as now.
- A tap on my name opens a small panel with signs and numbers: my color, my name with a button for a new random name, my locked bodies, my food, and the number of times that a worker or a player walked on one of my bodies.
- When I load the page again, also on a later day with the same save file, these numbers are there.
- The story list shows the number of walks for each player.

## Part 4: Other changes

### 4.12 Helpers, the session and small faults

- A helper obeys the guide: it locks where the guide shows, one lock each `16 / n` seconds, and carries food when the guide shows food.
- On `main`, change the default of the input `branch` of the workflow to `feat/0004-the-road-north`, in a commit that has only this change. Start the workflow one time for 5 minutes and tell me the result.
- The picture of the story must show each name fully. In your picture 25, the name "Steady Berry 18" shows as "Steady Berry 1".
- Change the TLA+ contracts to the new rules: a lock uses a spare body and never a carrier, the number of carriers never decreases, a player with food cannot lock. `mix colony.contracts` must be correct.
- The save file has a new version. The server keeps an older file with a new name and starts a new world.

## 5. Tests that you must do

Do each test yourself. Find the bugs before I do.

### 5.1 Automatic tests

1. Twenty bodies lock as fast as the rules permit for 5 minutes of world time. The number of carriers never decreases, and food comes to the nest all the time while a pile has food.
2. The nest moves at each crossing. The carriers and the spare bodies get to the new place. A player with food can bring it to the new nest.
3. The sizes and the lowest values of the piles, from your table test.
4. With no player, the world does not change in 10 minutes. With a page that only looks, the same.
5. The order of the guide rules, and the rule "share the work".
6. A player with food cannot lock.
7. For 20 seeds and 20 rivers: the widths of the table, no way around a river, and a pile and a start of a bridge for each river.
8. The table test for each width from 5 to 27: no run stops.
9. A new name changes all the bodies of the player. A second join with the same secret number is the same player.
10. Save and load keep the nest, the old nests, the two kinds of workers, the players and their numbers.
11. The contracts.

### 5.2 Load test

The targets of plan 0001, in a world that is 20 rivers long, with 150 carriers, 200 spare bodies, 2,000 locked bodies, 20 clients and 8 helpers.

### 5.3 Play tests

Play in a real browser at 390 x 844 with real touch events. The script knows only what a person sees. Use exactly this script:

- Each 0.1 seconds: if the button shows the bright lock sign, tap it.
- If not: push the stick in a straight line to the mark of the guide if it is on the screen. If it is not, push in the direction of the arrow.
- If the body did not move for 1 second, push to one side for 0.5 seconds, then to the other side.
- **The slow script** is the same, but it waits 6 seconds at the start, 0.5 to 1.1 seconds before each tap, and 0.3 to 0.6 seconds after it.

**If a target fails with this script, do not make the script smarter.** Change a number of section 4.3 and tell me, or stop and tell me why the rule fails. Use three seeds or more for each test.

1. **One slow player, 15 minutes.** Targets:
   - The first food is at the nest in less than 60 seconds.
   - The player crosses river 5 in less than 12 minutes.
   - The player never has more than 20 seconds with no guide and no bright button.
   - At the crossings of rivers 2 to 5, the colony has 60 spare bodies or fewer. This shows that the food has a value.
2. **One fast player, 5 fast players and 20 fast players**, 10 minutes each, with no browser. Targets:
   - The time to the crossing of river 4: 20 players are not slower than 5, and 5 are not slower than 1.
   - The rivers that are crossed after 10 minutes: 20 players have as many as 5 or more, and 5 have as many as 1 or more.
   - Each client makes one lock or more. With 5 and with 20, each client carries food one time or more.
   - No client has more than 20 seconds with no guide and no bright button.
   - Tell me the locks and the food of each client.
3. **The dead screen.** 4 carriers, 3 spare bodies and one fast player for 3 minutes. The player always has a guide or a bright button.
4. **My bodies.** A player locks 5 bodies, takes a new name, and loads the page again. All 5 bodies have the new name, and the panel shows 5 bodies and the walks.
5. **Two browsers.** The same records, the same story, and the two players see the same marks of the open cells.
6. **A long world.** 20 fast clients for 20 minutes. Then a browser opens the game and the story. Tell me the frame time, the size of the first messages, and the size of the picture.
7. **The session.** The result of section 4.12.

Make a screenshot of each of these: the two kinds of workers together, the move of the nest, each state of the button, the guide mark on an open cell, on the nest and on a pile, the "wider" phase with bright and weak cells, the panel of my name, lands 5 to 8, and the story of a world with 10 rivers. Put them in `docs/playtests/0004/`.

## 6. Rules for the work

- Branch `feat/0004-the-road-north`, from `feat/0003-the-crossing`. No pull request.
- The only change on `main` is the default branch of the workflow (4.12).
- Commit part 1 with its tests before you start part 2.
- Write each decision that this plan does not make in `docs/decisions.md`, from item 165.
- Write the report in `docs/playtests/0004-the-road-north.md`. For each target, write "met" or "not met" first. Write what the tests do not show. Write each thing that can confuse a player.
- All the text obeys `CONTRIBUTING.md`.

## 7. Not in this plan

- Lines of more than 4 bodies, and rivers wider than 27 rows.
- Rocks in a river, bodies that fall, floods, enemies and weather.
- A limit on the number of bodies that can walk on a bridge at the same time.
- A server that stays between play sessions.
- Accounts, chat, and names that a player types.

## 8. This plan is done when

1. I play alone on my phone for 10 minutes. I cross river 5 or more, and I never have a time with nothing to do.
2. With one or more other persons, we get farther in 10 minutes than I did alone.
3. With no spare body, I know what to do with no instructions.
4. I take a new name, and all my bodies have it. I load the page again, and my bodies are still mine.
5. Each lock feels good to me, and the sound is good.
