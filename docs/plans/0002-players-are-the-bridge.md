# Plan 0002: The players are the bridge

This plan has all the decisions for the second version of the prototype. Read all of it before you start. Read also plan 0001, `docs/decisions.md` and the report of play test 0001.

I did not merge plan 0001. Start the branch of this plan from `feat/0001-first-prototype`. The rules of plan 0001 stay on that branch. This plan replaces them where it says so.

## 1. What the first prototype showed

A play test of the branch gave these results.

- With 200 workers, a player holds Scent and goes forward. The workers build the bridge below the player. The player crosses in 5 seconds and does not lock one time.
- After one line of scent, the colony brings food with no player.
- Workers that build a bridge at a scent mark are in other ant games. A bridge of the bodies of real players is not. That is the part that I must test.
- With 0 workers, a new player crossed in 3 minutes 22 seconds with 28 bodies. The minimum is 19. A third body in a row gave nothing, and nothing told the player.
- For each body, the player walked about 5 seconds and made one decision.
- The workers completed the bridge in 3 seconds. That is too fast for a person to see.
- In a picture, a locked body and a body that walks look the same.

## 2. What this version must tell me

1. Is it fun to be the bridge, alone, in the first 2 minutes?
2. Do 5 to 20 persons build together with no chat?
3. Does a person want to see the record of a bridge that has the name of that person?

Build only what answers these questions.

## 3. New words

| Word | Meaning |
|---|---|
| river | The gap. Its width changes along its length. |
| pile | One pile of food on the far bank. There is one pile at a time. |
| helper | A body that the server controls with the rules of a player. |
| reach | The number of rows that a bridge can still grow. |
| record | The saved data about one bridge: who made it, how fast, and how much food went across. |

## 4. Decisions

### 4.1 Workers do not lock

- A worker never locks.
- A worker follows scent, carries food, and is a spare body for the players (4.3).
- Each locked body is the body of a player or of a helper.
- Remove the rule that a locked body lets go. A locked body stays. It can fall.

### 4.2 The river and the piles

- The near bank has a straight edge, as before. The edge of the far bank changes with the seed. The width of the river is 5 to 16 rows.
- The narrowest place is 5 or 6 rows wide. It is not more than 6 columns from the nest.
- The first pile is across the narrowest place, 3 rows from the river.
- A pile has 300 units. It does not fill again.
- From the first lock after a pile appears, the pile loses 1 unit each second. This stops when the first worker takes food from it. Thus a fast bridge gives more food.
- When a pile has 0 units, the next pile appears across a wider place. The sequence of widths is about 6, 9, 12, 14 and 16 rows. After that, the places are random.
- A new pile is 8 columns or more from each complete bridge, if such a place exists.
- Show the pile from far away, as the light does now.

### 4.3 The player takes the body of a worker

- After a lock, the player gets the body of the free worker that is nearest to the locked body by steps on foot. A worker that carries food is not used.
- The player has the new body immediately. The camera goes to it smoothly.
- That worker is not a worker after that. The colony has one free worker fewer.
- A body that a player took cannot lock for 1 second.
- If the colony has no free worker that the player can get to, the player gets a new body at the nest after 3 seconds.
- The colony starts with 30 workers. The maximum is 200.
- The nest makes 1 new worker for each 10 units of food that the workers bring.
- If the colony has fewer than 5 free workers, the nest also makes 1 worker each 10 seconds.
- Thus scent has a use for a builder: scent brings workers to the bridge, and the workers near the bridge are the next bodies.
- Show the number of free workers on the page, with a clear sign. It is the number of bodies that the colony can still use.
- Give the food number a clear sign also.

### 4.4 Support rule: each body beside a body helps

- The cost of a locked body is 1 divided by `n`. `n` is the number of locked bodies in the line of bodies with no hole, in the same row, that contains the body. The maximum of `n` is 4.
- Thus the cost is 1, 1/2, 1/3 or 1/4.
- The bank support stays 8.
- Calculate with integers: the bank support is 96, and the costs are 12, 6, 4 and 3.
- The results: a bridge one body wide stops at 7 rows. Two bodies wide stops at 15 rows. Three bodies wide stops at 23 rows.

### 4.5 Show the reach

- Before a lock, the player must see how far the bridge can go.
- From the cell that the page selects, show one mark on each row that the bridge can get to, if the player locks there and then continues one body wide to the far bank.
- When the selected cell is beside a body, the marks show the new reach. The player then sees that a body beside a body makes the reach longer.
- Use no words for this.

### 4.6 Helpers

- A helper obeys the rules of a player: the same speed, the same lock rule, the same 1 second, and it takes the body of a worker.
- A helper locks one time each 4 seconds at most.
- A helper builds to the pile. It starts at the cell of the near bank that is nearest to the pile, or it continues the bridge that is nearest to the pile.
- If a helper cannot lock in the next row, it locks beside the body that gives the longest reach.
- The names are "Helper 1", "Helper 2" and so on. A helper has a grey color. The page must show clearly that a helper is not a person.
- The number of helpers is a config value. The default is 0. `COLONY_HELPERS` changes it for one run.
- The demo mode has 4 helpers and no player. The bridge must grow slowly so that a person can see it.

### 4.7 The look of a bridge

- A locked body must look as a part of a structure. It is flat and low. Its legs go to the bodies that it touches.
- Free bodies walk on top of the locked bodies.
- A person who sees one picture must know which bodies are the bridge.

### 4.8 The record

- Count, for each locked body, the free bodies that went on it. Save the number. Show it with the name and the time when a player taps the body.
- When the first food of a pile gets to the nest, make a record of the bridge. The bridge is the group of locked bodies that touch each other, that touches the two banks, and that the first worker with food crossed.
- A record has: the time, the seconds from the first lock to the first food, the names with the number of bodies of each name, and the number of rows.
- When the pile has 0 units, add to the record the food that got to the nest from that pile.
- At the first food, show the record for 5 seconds to each player who has a body in the bridge.
- A button opens the list of all records, the newest first.
- Keep the records in the save file.

### 4.9 A play session on a runner

- Make a workflow that I start by hand. Its inputs are the minutes (60 by default, 120 at most), the number of workers and the number of helpers.
- The workflow starts the server on a runner and opens a quick tunnel of Cloudflare. Use the method of `.github/workflows/remote-ssh.yml` in `sntran/BEAM.com`. The job gets no secret.
- The workflow writes the address in the summary of the job.
- At the end, the workflow saves the world file and the records as an artifact.

### 4.10 Faults to repair

1. In `test/play/browser.js`, `touch.up(id)` lifts the wrong finger when two fingers are down. The event `touchEnd` must have only the finger that goes up. Thus no test of plan 0001 used two thumbs.
2. A message "lock" with an `at` value that is not text stops the channel of that player. A message with wrong data must not stop a channel.
3. A player who goes along the side of the pile, 1.4 cells from its center, gets no message. Use 2 cells.

## 5. Tests that you must do

Do each test yourself. Find the bugs before I do.

### 5.1 Automatic tests

1. With no player and no helper, and with scent from the nest to the river, no body locks in 5 minutes of world time.
2. A bridge one body wide stops at 7 rows, two wide at 15, three wide at 23.
3. The calculation with integers gives the same result as a full calculation.
4. After a lock, the player has the body of the nearest free worker in the next tick, and the colony has one free worker fewer. With no free worker, the player is at the nest after 3 seconds.
5. Ten units of food at the nest make one worker. With fewer than 5 free workers, the nest makes one worker each 10 seconds.
6. A pile loses units from the first lock to the first food. A pile with 0 units makes the next pile at a wider place.
7. A record has the correct names, numbers and times. Save and load keep the records and the counts of the bodies.
8. Four helpers and no player complete the first bridge in less than 60 seconds of world time. They bring food from a pile across 12 rows in less than 5 minutes.
9. The TLA+ contracts agree with the new rules, and `mix colony.contracts` is correct.

### 5.2 Load test

Use the targets of plan 0001, with 1,000 workers, 20 clients and 8 helpers.

### 5.3 Play test

Play in a real browser at 390 x 844 with real touch events. Keep one thumb on the stick while the other thumb taps Lock or holds Scent.

1. **A new player alone** (30 workers, 0 helpers). The player pushes forward and taps Lock when the button is bright. If the button is not bright, the player tries the two sides, then one step back. Targets: the first food is at the nest in less than 90 seconds from the load. The player crosses a place 12 rows wide with 24 bodies or fewer.
2. **One player and 3 helpers.** The record of a bridge has the name of the player and the names of helpers.
3. **Two browsers and 2 helpers.** One record has the two names of the players. Each browser shows the same record.
4. **Demo mode.** The first bridge grows for 15 to 45 seconds. Then food goes across. Make pictures at 5, 15 and 30 seconds. Make sure that the bridge bodies and the walkers look different.
5. **The play session.** Start the workflow one time. Open the address on a phone size and join. If you cannot start a workflow, say so in the report.

Write the report in `docs/playtests/0002-players-are-the-bridge.md`, as for plan 0001. If a target is not met, say so.

## 6. Rules for this repo

- Obey `CONTRIBUTING.md`.
- Put this plan in `docs/plans/`.
- Work on the branch `feat/0002-players-are-the-bridge`. Do not open a pull request.
- Add the decisions of this plan to `docs/decisions.md`.
- The numbers in section 4 are a start. Keep them in `config/game.exs`. If a test shows a problem, change the number and record the change.
- Stop and ask me only in two cases: a target cannot be met after real work, or a change is necessary in section 2 or in 4.1.

## 7. Not in this plan

- Accounts, and names that only one person can use.
- Chat.
- A way to remove a locked body.
- Enemies, floods, towers and rafts.
- A world that grows.
- The WebAssembly target.

## 8. Done when

- All tests in section 5 are done and the report is in the repo.
- I can start a play session, open the address on my phone, and bring the first food to the nest in less than 2 minutes with no instructions.
- I can give the address to other persons, and each of them can see a record with their name in it.
