# Decisions

The plans do not decide everything. This file records what I selected, and each rule that I
changed after a test. The newest plan is at the bottom.

## Plan 0001: First prototype

### Stack

1. **BEAM.com release.** The address `releases/latest/download/beam.com` of the BEAM.com
   README gives "404": all the releases are release candidates, and GitHub does not call a
   release candidate "latest". I use the newest release, `v0.1.0-rc.8`. It has Erlang/OTP
   29.1.2 and Elixir 1.20.5. The other versions are Phoenix 1.8.17 and Bandit 1.15.0.
2. **No JSON package.** Phoenix uses the `JSON` module of Elixir. The only packages in
   `mix.exs` are `phoenix` and `bandit`. All the packages in the lock file are Erlang or
   Elixir only.
3. **No build step for the page.** The page is plain JavaScript modules in `priv/static`.
   The channel client is the file `phoenix.mjs` of the Phoenix package. The plug
   `ColonyWeb.Static` sends the files with gzip. The first load is 43 KB after compression.
4. **The key of the endpoint.** The prototype has no accounts and signs nothing. The server
   makes a new random key at each start. `SECRET_KEY_BASE` can set it.
5. **Values from the environment.** `COLONY_WORKERS`, `COLONY_SEED` and `COLONY_SAVE_FILE`
   change the config for one run. The play test with 0 workers uses them.

### World

6. **The grid.** The rows with an odd number are half a cell to the right. The distance
   between two cells that touch is 1. Thus "4 cells each second" is 4 units each second in
   all directions.
7. **The nest and the food.** The nest is in row 7 of the near bank (of 14), in column 30.
   The food is in the same column, in row 4 of the far bank. The camera shows the food from
   the nest.
8. **The end of the world.** There is no wall. A body cannot go off the grid. Outside of
   the grid the ground goes up and has no cell lines.
9. **Stones and grass** are only for the look. A body goes through them.

### Messages

10. **The position of a player.** The page moves the body of its player and sends the
    position 10 times each second. The server checks each position: the cell must be a bank
    cell or a locked body, and the distance must agree with the speed. If not, the server
    keeps the old position and sends it back. This is the simplest option that has no delay
    for the player. The server holds the truth.
11. **The position of a worker.** A worker goes from cell to cell. The server sends 2 bytes
    for each step: the number of the worker and the direction. The page moves the picture
    of the worker smoothly at 4 cells each second. Thus 1,000 workers need about 7 KB each
    second.
12. **Limits of the format.** A move has 13 bits for the number of the worker, thus the
    maximum is 8,191 workers. A player number has 16 bits. A later plan with more bodies
    must change the format, but only the file `lib/colony/protocol.ex` and the file
    `priv/static/js/state.js`.
13. **Scent in the messages.** The server sends a scent value only when a body changes it.
    The page subtracts 1 each second, as the server does.
14. **Join.** The snapshot goes out after the join, when the channel gets the ticks. The
    page keeps the ticks that come before the snapshot and uses the newer ones after it.

### Lock, support and fall

15. **Which cell.** A body can touch more than one cell where a lock is possible. The page
    selects the cell in the direction that the body looks. It shows that cell full and
    bright, the other possible cells with a yellow outline, and the cells where a lock is
    not possible with a red outline.
16. **"Its support will be more than 0."** The server calculates the support that the new
    body gets, with the lower cost of the bodies beside it. It does not use the old values
    only. A test compares this calculation with a full calculation.
17. **Fall.** All the bodies with support 0 or less fall at the same time. Then the server
    calculates again, and does this until no body falls.
18. **A free body on a body that falls** falls also. A worker starts again at the nest. A
    player gets a new body at the nest after 1 second, as after a lock.
19. **Low support shows.** A locked body with support 2 or less gets red and shakes. The
    lower the support, the more red. This tells a player why the bridge stops.

### Workers

I changed no number of sections 4.3 and 4.6. These are the points that the rules do not
decide.

20. **The order of the rules.** At each step a worker uses the first rule that applies:
    carry, go to food, bridge, go out, move at random.
21. **Where a bridge starts.** A worker starts a bridge only from a cell on the edge of the
    near bank that has scent. Thus the scent of a player tells the workers where to build.
22. **"Scent near"** is scent on a cell that touches the cell of the worker.
23. **"The end of the bridge"** is the end of the way that the worker follows: from its
    cell, always to a locked body in the next row. If a body can lock there, the worker
    goes there. If not, the worker locks beside the first body that it is on and that is
    alone in its row.
24. **The side.** A worker that locks beside a body takes the side that touches more
    locked bodies. The bridge then stays straight.
25. **Too far.** A worker with no scent near that is more than 6 cells from scent and from
    the nest goes home by the shortest way. Thus a worker that crosses a bridge and finds
    no food comes back. If the bridge of a player is far from the food, the player must put
    scent on the far bank.
26. **No way home.** A worker on the far bank with no bridge moves at random there and
    waits for a bridge.
27. **Rest.** A worker that moves at random stays where it is half of the time.
28. **Use of a locked body.** A free body that stands on a locked body uses it, as a body
    that goes on it. Thus a bridge does not let go below a player who waits.
29. **Let go.** A locked worker that lets go steps to a cell that touches it: a bank cell,
    or the locked body with the most support. If there is no such cell, it falls and starts
    again at the nest.
30. **Scent on a bridge.** A cell with a locked body can have scent. Workers follow it.
    The page shows scent only on the ground.

### Food

31. **The pile fills again.** 200 workers take the 500 units in about 1 minute. Then the
    world has no goal and the demo mode has nothing to show. Thus the pile becomes full
    again 60 seconds after it becomes empty. `food_refill_seconds: nil` stops this.
32. **A player does not carry food.** When a player touches the food for the first time,
    the page shows a message with the time from the load of the page.

### Save

33. **The file** is `priv/data/world.bin`: one Erlang term. Git does not track it.
34. **What is not in the file:** the free workers and the players. After a load, the locked
    workers are locked, the other workers start near the nest, and the time to let go
    starts again.
35. **Shutdown.** The server saves when it stops in the usual way (the signal `TERM`).
    Two times Ctrl+C stops the VM immediately, with no save. Then the world is as it was at
    the last save, 30 seconds ago or less.

### Player and page

36. **The name** is two words and a number, for example "Swift Fern 27". The server keeps
    letters, digits, spaces, "-" and "_", and 16 characters at most.
37. **The color** of a player is a bright color from a hash of the name. Workers are dark
    brown. A locked body of a player keeps the color.
38. **The stick** shows at the lower left. When the thumb touches the lower left part of
    the screen, the stick moves to the thumb.
39. **The mark of the player.** A white triangle is above the body of the player, and a
    white ring is below it. With 200 workers near, the body was not easy to find.
40. **The time of a lock** is the clock of the server in seconds. The page shows it as a
    local date and time.
41. **Fewer pixels.** The page uses 2 canvas pixels for each page pixel at most. If the
    picture is below 27 frames each second for 3 seconds, the page uses fewer pixels.
    `?scale=1` sets the number and stops the automatic change.
42. **Smooth edges.** A screen with 2 or more pixels for each page pixel gets no smooth
    edges from the graphics card. The picture is then faster, and such a screen does not
    need them. A phone has such a screen.
43. **Slow frames.** The body of the player moves with the real time. A slow frame does not
    make the body slow.

### Demo mode

44. **A demo client has no body.** While one or more demo clients are there, the server
    puts scent on the straight line from the nest to the gap. The front of the scent moves
    at the speed of a body. The world is the same world that the players see.
45. **The camera** goes from the nest to the middle of the gap in 14 seconds and turns
    slowly. For a video from an empty gap, use `mix colony.reset` first.

### Load test

46. **The clients** are real WebSocket connections from the same VM. Each one joins as a
    player and moves 10 times each second near the nest. One of three puts scent. The scent
    of the demo mode is on, thus the 1,000 workers build a bridge and carry food.
47. **The bytes** are all the bytes that a client gets after the handshake, with the
    WebSocket frames and the channel headers.

### Play test

48. **A script plays.** The scripts in `test/play/` open the page in Chromium. They use
    real touch events at 390 x 844 and real key events at 1280 x 800. They read the state
    of the page to decide where to go. They need Node.js and Playwright. They are not part
    of `mix test`.
49. **The player of the script** goes to the end of the bridge and locks in the next row.
    If that is not possible, it locks beside the body that is nearest to the end and alone
    in its row.

### TLA+ contracts

These decisions are from the work after the report: I added contracts in TLA+ and the
native TLA+ checker of accord.

50. **The package.** `accord` comes from the branch `feat/native-tla-checker` of
    `sntran/accord`. `mix.lock` has the commit. It is a package for development and tests
    only: the server that runs does not have it. It brings 8 other packages (pentiment,
    makeup, makeup_elixir, makeup_erlang, nimble_parsec, propcheck, proper, libgraph). All
    are Erlang or Elixir only.
51. **Two contracts.** `specs/Bridge.tla` has the lock rule, the support rule and the
    fall. `specs/Colony.tla` adds the free body of each player. `specs/README.md` tells
    what each one says.
52. **Half units.** The contracts use integers. A support or a cost in a contract is two
    times the number of `config/game.exs`.
53. **Small models.** The checker looks at all the states of a gap 2 cells wide and 3
    rows, with bank support 2.0. With these numbers a bridge one cell wide stops at 1 row
    and a bridge two cells wide crosses, as the numbers of the plan do at 7 and 12 rows.
    The model with the numbers of the plan is one cell wide. A gap 2 cells wide and 12
    rows has too many states for a check of all of them: a test follows one bridge there.
54. **The monitor is in the tests, not in the server.** A step of the monitor is an
    interpreter of TLA+. It takes some milliseconds. The server has 100 ms for a tick
    with 1,000 workers.
55. **A move in the contract is a move to a cell.** The contract says: a free body goes
    to its cell or to a cell that touches it. The real world has positions. The test
    moves a body from the center of a cell to the center of a cell.
56. **Rule change: a move cannot go across a cell.** The monitor found that the world
    accepted a move to a cell two rows away, across a cell where a body cannot be. The
    world looked only at the end of a move and at its length. A changed client could jump
    across a hole of one cell. Now a body can keep the movement for 1.5 cells, not 2.0,
    and the world looks at points along the straight way of each move. A point can be 0.2
    cells into a cell where a body cannot be: a body that goes around a corner between
    two messages does this.
57. **An event for the tests.** The world records the cells of the workers that let go.
    The clients do not get this event. The contract tests need it: the step `LetGo` of
    the contract has the set of these cells.
58. **Where a worker can lock.** `Bridge.tla` explores bridges that grow from the near
    bank: all the free bodies come from there. `Colony.tla` has no positions of workers,
    thus a worker can lock there into each cell that will have support.
59. **`mix colony.contracts`** calls the checker for each module. I do not use
    `mix accord.check` for this: its engine sets the deadlock check to "on" and does not
    read `CHECK_DEADLOCK FALSE` from the config file. A bridge of bodies of players only,
    with no cell where a lock is possible, has no next step. That is correct, not a fault.
60. **Slow checks.** `mix test` runs the checks that take seconds. The check of
    `Colony.tla` and of `BridgeWide.tla` take minutes: `mix test --include slow` or
    `mix colony.contracts --all`.

## Plan 0002: The players are the bridge

The rules of plan 0001 that this plan replaces are not in the code: workers that lock,
locked bodies that let go, the pile that fills again. The decisions 16 to 18, 20 to 31, 44,
45, 49, 52, 53, 57 and 58 above are history. They are true on the branch
`feat/0001-first-prototype`.

### Numbers that I changed

61. **A helper locks one time each 16 seconds, not each 4.** With 4 seconds, the 4 helpers
    of the demo mode completed the first bridge 7 seconds after the start. The plan wants
    15 to 45 seconds. `helper_lock_seconds` is 16. The helpers also lock in turn: with
    `n` helpers, one lock each `16 / n` seconds. Thus 4 helpers make one lock each 4
    seconds, and a person sees each body. The first bridge of the demo mode is complete
    after 23 to 27 seconds.
62. **The widths of the piles.** The first pile is across the narrowest place: 5 or 6
    rows. `pile_widths` has the widths of the next piles: 9, 12, 14 and 16. A pile goes to
    a column with that width, or with the nearest width that the river has.
63. **`food_touch`** is 2.0 cells (fault 3 of section 4.10). All the other numbers of
    section 4 are the numbers of the plan.

### The river

64. **How the river comes from the seed.** The width of each column is a sum of three
    sine waves, from 8 to 16 rows, with a valley to 5 rows near the nest. The world tries
    seeds until the river obeys these rules: the width changes by 2 rows or less from one
    column to the next, the narrowest place is 5 rows, and each width of `pile_widths` is
    there. A test checks the rivers of 40 seeds.
65. **The far bank is deeper than 14 rows where the river is narrow.** The grid has 14
    rows of far bank after the widest place. All the cells after the river are far bank.
66. **The page gets the width of each column** in the snapshot, with the seed. The page
    makes the ground, the bank and the water from these numbers.
67. **A new pile** is in a column that the old pile did not have. It is 8 columns or more
    from each complete bridge, if such a column exists. Of those columns, the world takes
    one at random from the columns with the best width.
68. **The loss of a pile** starts at the first lock after the pile appears. If no body
    locks, the pile loses nothing. If the loss makes the pile empty, the next pile appears
    and there is no record.
69. **The far bank is one piece of land.** After the first complete bridge, a body can
    walk along the far bank to each later pile, and scent leads the workers there. See
    the report: this is the largest risk for the design of the piles.

### The body of a worker

70. **"Nearest by steps on foot"** is a search from the locked body across the bank cells
    and the locked bodies. Thus a worker on the other bank with no bridge is never the
    next body.
71. **The reply to a lock** has the position of the new body. The page puts the body of
    the player there and moves the camera to it in about half a second. If the reply has
    no body, the camera goes slowly to the nest, and the new body is there after 3
    seconds. The page shows no sign for this wait: see the report.
72. **The number of a worker.** A worker that a player takes gives its number back. The
    next new worker uses it. Thus the numbers stay small in the messages.
73. **The limit of 200** is for the free workers. Locked bodies and the bodies of players
    do not count.
74. **Food for a worker.** The nest counts the food. Each 10 units make one worker. At
    the limit, the count stops at 10.
75. **The save file has the number of free workers, not their places.** After a load,
    the workers start near the nest.

### Workers

76. **The rules of a worker**, the first rule that applies: carry food to the nest, go to
    a pile that is 6 cells away or less, go along a bridge to the far bank, go out along
    scent, move at random near scent or near the nest.
77. **Workers wait at the end of a bridge** that is not complete, if that end is 6 cells
    or less from scent or from the nest. They are the next bodies of the builder. This is
    the use of scent in section 4.3.
78. **The way to the pile and the way across** are searches on the cells where a body can
    be. The first rule was "go to the cell that is nearer". With it, workers went from
    one cell to the other and back at a corner of a bridge, and no food went across.
79. **A worker keeps one locked body of its way.** The record needs it: the bridge of a
    record is the group of bodies that has this body.

### Support, lock and reach

80. **A lock is a full calculation** for the group of bodies that the new body touches.
    A new body changes the cost of all the bodies of its line. The calculation takes the
    highest support first (the method of Dijkstra), with integers.
81. **Nothing removes a body, thus no body falls in a game.** A new body never decreases
    a support: the contract `SupportOnlyGrows` shows this. The function that makes bodies
    fall is in `lib/colony/support.ex` for a later plan and has a test. The world does
    not call it.
82. **The page calculates the support also.** `priv/static/js/support.js` has the same
    rule with the same integers. The page needs it for the reach before a lock. The play
    test compares the supports of the page with the supports of the server.
83. **The reach marks.** A yellow mark is on each row that the bridge can get to. A large
    green mark on the far bank tells that the bridge gets across. If it does not, a small
    orange mark is on the first row that the bridge cannot get to. The orange mark is
    larger when the bridge almost gets there. A wave goes along the marks, away from the
    bridge. There are no words.
84. **A body with low support** is red and shakes, as in plan 0001. Low is 2 or less of
    the 8 of the bank.

### Helpers

85. **A helper is a player with no connection.** It uses the same functions for the move
    and the lock. Thus it obeys the same rules, and its lock gives it the body of a worker.
86. **Where a helper locks.** In the next row, into the cell nearest to the pile. If no
    lock is possible there, beside the body where the new reach is the longest.
87. **When the work is done.** A helper stops when a complete bridge is fewer than 8
    columns from the pile. Then it does the next item.
88. **Helpers show the way.** One time for each pile, a helper goes from the nest across
    the bridge to the pile and puts scent. Without this, the 30 workers did not find the
    later piles in the demo mode, and no food went across.
89. **The demo mode** makes 4 helpers while a demo client is there. They go away when the
    last demo client goes. Their locked bodies stay. The camera looks at a point between
    the helpers and the pile, and turns slowly.
90. **The look of a helper.** Grey, with a name label that has a line of dashes around it.
    In a record, the name of a helper is grey also.

### The look of a bridge

91. **A locked body** is flat and lower than a body that walks. A dark plate is below
    it. Each of its 6 legs goes to the edge of the cell if a body or the bank is in that
    direction. If not, the leg stays short. All the locked bodies look to the far bank.
    The color of the player stays on the body.

### Records

92. **The seconds of a record** go from the first lock after the pile appeared to the
    first food of that pile at the nest. With no lock for a pile, they go from the moment
    when the pile appeared.
93. **The rows** are the rows of the river that have a body of the bridge. The record has
    also the width of the river at the pile and the number of bodies.
94. **The record is complete** when its pile has 0 units and no worker carries food of
    that pile. The page shows "and more" after the food number before that.
95. **Who sees the record.** The server sends each record to all the clients. The page
    shows the card for 5 seconds only if the name of its player is in the record. The
    list has all the records.
96. **`mix colony.records`** prints the records of the save file as JSON. The play
    session uses it for the artifact.

### Messages and page

97. **A body on the edge of a cell.** The page sends positions with 3 decimals. The server
    accepts a position that is 0.004 cells or less into a cell where a body cannot be.
    Before this, the server refused small moves along the bank, and the body jumped back.
98. **After a lock, the page sends no move** before the reply comes. A move that was on
    its way would put the new body at the old place.
99. **The buttons use `pointerup`.** With one thumb on the stick, a browser does not make
    a `click` event for the second finger.
100. **Wrong data from a client** gets the reply "error". The channel continues (fault 2
     of section 4.10).
101. **The two numbers at the top** have signs that the page draws: a body for the free
     workers, and three grains for the food.

### The play session

102. **The workflow** has one job. It gets no secret, and its token can only read the
     repo. The actions have the full commit hash. The script gets `beam.com` and
     `cloudflared` from their releases and compares the SHA-256 of each file with the
     value in the script.
103. **The server runs with `MIX_ENV=prod`.** Thus the checker package is not there.
104. **If the tunnel stops**, the job fails. The artifact has the world file all the same.
105. **GitHub starts a workflow by hand only if its file is on the default branch.** The
     branch of this plan is not merged. Thus I could not start the workflow: see the
     report.

### Tests

106. **The script of the play test** obeys section 5.3: it pushes forward and taps "Lock"
     when the button is bright. If the button is not bright, it tries the two sides, then
     one step back. The left thumb stays on the stick. For the bridge across 12 rows, the
     script uses a place where the 3 columns on each side are 12 rows wide or more. At a
     place with a narrower column beside it, a bridge ends on that bank with fewer rows.
107. **The load test** has 8 helpers that build bridges to the piles. The workers carry
     food all the time. The clients move near the nest, and one of three puts scent.

### TLA+ contracts

108. **The integers of the contracts are the integers of the server**: 96 for the bank,
     and 12, 6, 4 and 3 for the costs. `Costs` and `River` are constants.
109. **No fall and no "let go" in the contracts.** A step can only add a body.
110. **15 and 23 rows.** A model with all the bridges two bodies wide has too many
     states. The contract uses this: more bodies never decrease a support. Thus the
     river with a body in each cell gives the highest support that a row can have. The
     checker looks at that one state.
111. **Workers are not in the contracts.** A worker changes no locked body. The contract
     of the player says only that a lock gives the body of a worker, or no body.
112. **The monitor test** has one helper and 5 workers in its world. The world tells the
     monitor three events: a helper locked, a body can lock again, and a player has a new
     body at the nest.

## Plan 0003: The crossing

These are the decisions that the plan does not make. The plan is
[`0003-the-crossing.md`](plans/0003-the-crossing.md).

### Numbers that I changed

113. **3 units of food make one worker, not 5.** With 5, a new player who locks fast gets
     to river 4 with 4 spare bodies. Then each lock uses the worker that the nest made a
     moment before, and the new body is far from the bridge. With 3, the same player gets
     to river 4 with 20 to 30 spare bodies and never waits. The plan permits this change.
114. **A player takes food at 0.75 cells from the center of a pile.** A body that walks
     on a cell beside a pile does not take food. With a larger distance, a player on the
     way to the next river took 10 units and lost them at the next lock.
115. **With no bridge, the workers wait 6 columns or less from the column of the pile, not
     3.** The first body of a bridge can lock 6 columns from the pile. With 3, the first
     lock of a bridge gave a body that was 5 cells away. The number is `start_columns`:
     the workers wait on the cells that touch an open cell.

### The world

116. **Each land after a river is 8 rows deep at the widest place of the river.** At a
     narrower place it is deeper. The world has 96 rows. Each river has a place with its
     least width and a place with its largest width.
117. **A position in a message has a step of 0.002 cells.** The world is longer than 64
     cells, and a position is 16 bits.
118. **Pile 1 loses units from the first tick of the world**, as the plan says: no body
     can walk to it. A server that waits one minute for its first player has a pile of
     240 units. See the report.
119. **A pile with 0 units stays.** No new pile comes from an empty pile.

### Open cells and locks

120. **The page gets the open cells from the server.** The server sends all the open
     cells each time a body locks. Thus the page and the server cannot have different
     rules. The page calculates no support. The marks of the reach of plan 0002 are
     gone: the open cells show where a lock helps.
121. **"Forward" is the row after the top row.** A cell of that row is open if it touches
     the bridge and a body there has support. Support from the far land counts. Thus the
     last body of a bridge is open as soon as the bridge is one row from the land.
122. **"Wider" compares the highest support of the top row** before the lock and after
     it. If the new body is in the top row, its support counts also.
123. **The colony builds across one river at a time.** River `k + 1` has no open cell
     before the crossing of river `k`: its pile is not there.
124. **Each worker is a spare body**, also a worker that carries food. The number at the
     top is the number of workers. A lock uses the nearest worker with no food. If all
     the workers carry food, it uses the nearest worker, and the player has the unit of
     food of that worker.
125. **A lock that the server refuses makes no error on the screen**: a second player got
     the cell, or the last spare body. The button is not bright after that.

### Workers

126. **One worker waits on each cell.** The workers that wait go as near to the crossing
     place as possible. The crossing place is each cell where a body can stand and lock
     into an open cell: the edge of the land before the first lock, then bodies of the
     bridge. Thus the workers make a line on the bridge and a crowd behind it, and a
     lock at each open cell finds a spare body near.
127. **"One of each three waits" is a count.** The world keeps the number of workers that
     wait at the number of workers divided by 3, to the next integer. A worker that
     starts to wait is the worker with no food that is nearest to the crossing place.
128. **A new pile calls workers.** Without a rule for this, the workers go to the nearest
     pile, and the first food of pile 4 comes only when piles 1 to 3 are empty: the
     world does not get complete. Thus:
     - At a crossing, all the workers that waited go across the bridge. The worker at
       the end of the line goes to the new pile. The others go to the next crossing
       place. After the last crossing, all of them go to the pile.
     - Until the first food of a pile is at the nest, 3 workers go to that pile or carry
       food from it. They are the workers with no food that are nearest to the pile. A
       worker that waits at the crossing place is called only if no other worker is
       there.
129. **A worker number is not used again in the tick of its lock.** A client then gets
     "worker gone" and "worker set" of one number in two messages.

### Food and records

130. **The record of a bridge is made at the crossing.** It has the bodies of each name
     in that bridge, the seconds from the first lock of the bridge to the crossing, the
     units of the pile at the crossing, and the width of the river in the widest column
     of the bridge.
131. **The food of a player counts in the record of the bridge that the colony builds at
     that time.** Food after the last crossing counts in the last record. The story has
     all the food of each player.
132. **A player puts food into the nest at 1.5 cells from the nest.**

### Helpers

133. **The helpers lock in turn.** After its lock, a helper waits until the other helpers
     had time for theirs. A helper takes food only when it goes for food.

### The page

134. **The arrow shows the way on foot**, not the straight line: it points along the
     land and the bridges to its target. The order of its rules is the order of the
     plan: an open cell if the colony has a spare body, then the nest if I carry food,
     then a pile if the colony has no spare body.
135. **The way of the arrow does not go across a pile.**
136. **The body goes around a corner.** If the push of the stick is blocked by water, and
     the player pushes in the direction of the target of the arrow, the body goes along
     the way on foot for half a second. Without this, a body on a side body of a wide
     row cannot get to the open cells with a push "at what I see".
137. **A client that only looks has no body**: the demo mode and the story.
138. **The water is 0.3 cells below the land**, not at the bottom of a deep gap. The
     locked bodies are at the level of the land, a small distance above the water.

### Save

139. **A save file of an older version gets the name `world.bin.v2`** (the number is its
     version). The server then starts a new world.

### Tests

140. **The script of the new player** is `test/play/newplayer.mjs`. "The body did not
     move" is: the place of the body in the world changed less than 0.03 cells in 0.1
     seconds. While the right thumb taps, the left thumb stays where it is.
141. **The 20 clients with no browser use the code of the page** for the world, the body
     and the arrow, and the same script. They calculate what a person sees on a screen
     of 390 x 844 from the camera of a player.
142. **The table of section 4.5.** "Best" takes the open cell that gives the highest
     support of the top row. My "Random" row is not the row of the plan: the highest of
     25 random runs changes with the random numbers. In 3,000 runs at width 10, 13
     bodies came 2,959 times and 14 bodies 41 times.

### TLA+ contracts

143. **`Bridge.tla` has one river.** The rule for each river of the game is the same. A
     test makes the contract of river 1 and of river 2 of the real world.
144. **Two models of a bridge.** `Bridge` and `BridgeWide` let a body lock into each cell
     where it has support: they check the support rule in all the structures.
     `BridgeOpen` permits only locks into open cells: it checks the rules of the open
     cells.
145. **`BridgeNineRows` has the numbers of the plan**: a river of 9 rows needs 10 bodies,
     and no bridge stops before the far land. This check needs 80 seconds or more.
146. **The contract has the number of spare bodies, not the workers.** A lock subtracts
     one. The nest adds one. The contract permits each number of workers at the start.

### The moment of a lock and of a crossing

147. **The order of a lock on the page.** The note plays and the phone shakes when the
     reply of the server comes. The light starts at the same time and flies for 0.4
     seconds. The locked body goes down when the next message of the server has the lock:
     0.1 seconds later or less. The ring on the water starts when the body is down.
148. **The new body has the color of a worker while the light flies.** When the light
     gets to it, it gets the color of the player and is large for a moment. The mark
     above the body shows again at that time.
149. **Each player sees the light of each lock**: the light of an other player flies to
     the new body of that player, in the color of that player.
150. **The camera shows the full bridge** only to a player who has a body in that bridge
     or who is 40 cells or less from it. The other players get the record card
     immediately. A change of the stick stops the camera after the first 0.3 seconds:
     at the lock, the thumb is on the stick.
151. **The record card shows after the camera**, for 6 seconds. The light and the number
     of the next pile appear 3.4 seconds after the crossing.

### Sound

152. **The keys of the rivers** are G, D, B flat and G one octave lower: a longer river
     has a lower key, thus the note of its last row is not too high. The scale is 0, 2,
     4, 7 and 9 half tones. Row 1 is the first note, row 6 is one octave higher.
153. **The limit is 8 lock notes each second.** The note of my own lock always plays. A
     lock far away is quiet. The sounds of the nest play only near the nest, 4 each
     second at most.
154. **The page counts the notes** in `window.colony.sound.counts`. A test reads them.
155. **The sound is on at the start.** The button keeps its state on the device.

### The look

156. **The seasons are colors**: the ground, the grass, the stones, the fog and the
     light. The fog and the light change across each river. Spring has flowers, summer
     has tall grass, winter has not much grass.
157. **A worker that waits** looks to the pile across the river, moves its legs, and
     moves a little to the front and back.
158. **The page uses fewer pixels in steps**: 0.8 times at each step, down to 0.75
     canvas pixels for each page pixel.

### The story

159. **The time of the story** is 0.3 seconds for each lock: 20 seconds or more, 40
     seconds or less. The bodies appear at the same rate. The free bodies do not show
     while the story plays.
160. **The first tap on the cross goes to the end of the story.** The second tap closes
     it. The end shows the world from above, the names, and the record of each bridge:
     the list of the records of plan 0002 is here now.
161. **The page shows the story one time when the world gets complete** while the page
     is open, 5 seconds after the first food of the last pile. A page that opens a
     complete world does not start the story: the button does.
162. **The picture** is the world from above with 2 canvas pixels for each page pixel,
     and a part below it with the numbers of the world and the names. The date is the
     date of the first tick of the world. If the browser can share a file, the button
     opens the share function. If not, it saves the file.
163. **A new name** goes to the server in the message "name". The bodies that the player
     locked before keep the old name.

### The play session

164. **The workflow file is on `main` and on the branch.** The file on `main` gets the
     branch of its input and runs `scripts/play_session.sh` of that branch. It makes
     sure that the branch has `mix.exs` and the script.

## Plan 0004: The road north

### Numbers

165. **The factor of the size of a pile is 1.2, not 1.5** (section 4.3). With 1.5, the
     slow player of play test 1 had 70 and 87 spare bodies at the crossing of river 5
     (seeds 2027 and 11): more than 60. I tried two changes with the slow script and no
     browser, for 3 seeds. With 4 carriers for each crossing, seed 11 still had 69. With
     the factor 1.2, the seeds had 38, 39 and 27, and river 5 came at the same time. The
     other three numbers stay: 12 carriers at the start, 8 more at each crossing, and 5
     units for one spare body.
166. **The table of the open cells** uses the seeds 1 to 200 and the start columns 24 to
     36 of a river with the same width in all its columns. `mix colony.table` makes it
     again. The normal tests make the table with 25 runs. The test with 200 runs has the
     tag `slow`. A river narrower than 5 rows (only in tests) uses its width for `B` and
     `R`: a straight line is the best bridge there.
167. **The sizes of the piles are whole units**: `round(5 × 1.2 × R)` and
     `round(5 × 1.1 × B)`. Pile 1 is 114 units with 88 at the least. Pile 6 and each pile
     after it are 600 units with 517 at the least.

### Workers

168. **The look of the two kinds.** A carrier is 0.78 times the size of the body of a
     player and almost black. A spare body is the size of the body of a player and red
     brown. A carrier with food has a yellow piece in front of its head, and a carrier
     with an egg has a white egg.
169. **The eggs.** At a crossing, the 8 new carriers come out of the new nest and go for
     food at once. Each older carrier with no food goes to the old nest for an egg and
     brings it to the new nest. A carrier with food brings it to the new nest first.
170. **The crowd at the crossing place spreads.** A spare body that cannot go ahead goes
     to a free cell beside it that has a free cell in front of it. Without this rule, all
     the spare bodies stood in one line behind the first body.
171. **The way to the crossing place goes 30 steps past the nest.** A spare body that is
     farther away walks to the nest first. Thus a lock in a long world does not make a
     map of all the world.
172. **A carrier goes to the pile with food that is nearest to the carrier**, not to the
     nest. After a crossing, carriers can be on long trips to old piles. Automatic test 1
     thus checks that the time with no food is not longer than one trip to the farthest
     pile with food and 5 seconds.

### The nest

173. **The cell of the new nest** is 3 rows south of the body of the bridge with the lowest
     lock number, in its column. If that cell has a pile, the nest is on the nearest free
     land cell. The row is 0 or more.
174. **An old nest** is a low ring of earth with an empty hole, and the number of its land
     as a label.

### Piles

175. **The column of a pile comes from the seed and the number of the pile** (a hash), not
     from the random state of the world. One seed gives the same piles each time, and
     automatic test 7 checks the piles of 20 rivers from the grid only.
176. **A way on foot does not go across the cell of a pile.** The guide of the page and
     of the server use the same rule.

### The world stops

177. **A helper is not a player.** With only helpers in the world, the server makes no
     tick. A page that only looks is not a player.
178. **Each save has its own temporary file.** Before, the save when the last player goes
     and the save at the stop used the same file, and one of them failed.

### The guide

179. **The nearest target** is the target with the fewest steps on foot from the body.
     With the same number of steps, the target nearer in a straight line comes first,
     then the cell with the lower number. The page and the server have the same rule. A
     test compares them for 225 places of a body.
180. **The nest rule needs a way on foot to the nest.** The pile rule needs a pile on a
     land that the colony crossed to.
181. **"Players" in the rule "share the work"** are the players and the helpers in the
     world.
182. **The button "wait"** shows when no rule of the guide applies and no other state of
     the button applies. With no spare body, the button shows the body sign with 0: it
     is first in the table of section 4.7.
183. **The mark** is two rings in my color on the target. They turn, and they get larger
     and smaller. The arrow at the edge points along the way on foot, not in a straight
     line to the target.
184. **The gain of an open cell.** A cell ahead has the gain 0. In the "wider" phase,
     the server sends the increase of the highest support of the top row. The page makes
     the cells with the largest gain bright. When all the cells are ahead, all are bright.

### Messages

185. **A cell and a position along the world are u32** in all the messages. A position
     is `(value + 1) × 500`. The test makes a world of 32 rivers (more than 1,000 rows).
186. **A tick sends only the changes**: the supports that changed and the piles that
     changed. Section 15 of a tick sends the new rivers when the grid grows.
187. **The secret number** is 32 hexadecimal characters from `crypto.getRandomValues`, in
     local storage. The server keeps only its SHA-256. A join with no number makes a new
     person. The server accepts 16 to 64 letters and digits.

### The world with no end

188. **The grid grows at each crossing**: the server makes the grid again with the
     rivers as far as two rivers after the newest pile. The cells of the old grid do not
     change. For 23 rivers this takes about 130 ms, one time at a crossing.
189. **The page makes the world in parts of 24 rows.** It draws the parts that the camera
     sees before the end of the fog. The grass and the stones of a part come from the
     seed and the number of the part. When the grid grows, the page makes the new parts
     and the part at the old north end again.
190. **The seasons.** Land 0 and land 1 are spring, then summer, autumn and winter, and
     then spring again. The fog and the light change across each river.
191. **The end of the story** shows the full world above the list of the names. The
     picture of a long world has parts, from the north to the south, each with the full
     width of the world. A long picture has fewer pixels: about 6,000 in its length, but
     not less than one canvas pixel for each page pixel. Thus a very long world makes a
     longer picture: 390 x 7,268 pixels for 35 crossings.
192. **The names in the picture** are in two columns only when each name and its numbers
     fit. If not, they are in one column. The list on the screen has one column.
193. **The story button flashes 7 times** after a crossing.
194. **The demo page** shows the colony from the nest to the next river, not from land 0.

### My name

195. **A tap on my name opens the panel.** Before, a tap gave a new name at once. The
     button with two arrows in the panel gives the new name. The panel asks the server
     for its numbers each 2 seconds while it is open.

### The play session

196. **The input `workers` of the workflow is not used.** The config has the carriers and
     the spare bodies. The plan permits only one change on `main`, thus the input stays
     in the workflow file.
197. **The session with no player** does not tick: the artifact of a session with no
     player has a world with no lock.

### Tests

198. **The contract has one river.** The world now gets the next river at the crossing.
     Thus the monitor test stops at the crossing, and the test world of the contract
     takes the helpers away there.
199. **The world of the load test** comes from fast locks into random open cells, with no
     walk, until the colony crossed 20 rivers and has 2,000 locked bodies. With random
     cells the bridges are narrow: the world has 25 crossings when it gets to 2,000
     bodies.
200. **The fast clients of play test 2 have no browser.** They use the code of the page
     (the world, the guide, the button) and the script of the new player. The time with
     no guide and no bright button counts from 6.5 seconds after the join.
201. **Play test 6 compares the frame time with the same picture.** The young world has
     22 workers near the nest, and the long world 350, with bridges near the nest. The test
     thus measures the two worlds also with no body drawn: only the ground, the water, the
     grass and the stones. The target "the frame time does not increase" uses this measure.
     The report also gives the frame time with the bodies.
202. **Play test 5 compares the story with no walks.** The walks on the bodies are a live
     number, and the two pages ask for the story at two moments.
203. **The screenshots of lands 5 to 8 and of a story of 10 rivers** use a world from
     `test/play/make_long.exs`: 6 players lock fast, with no walk. The other screenshots
     come from play.
