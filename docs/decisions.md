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
   `ColonyWeb.Static` sends the files with gzip. The first load is 42 KB after compression.
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
42. **Slow frames.** The body of the player moves with the real time. A slow frame does not
    make the body slow.

### Demo mode

43. **A demo client has no body.** While one or more demo clients are there, the server
    puts scent on the straight line from the nest to the gap. The front of the scent moves
    at the speed of a body. The world is the same world that the players see.
44. **The camera** goes from the nest to the middle of the gap in 14 seconds and turns
    slowly. For a video from an empty gap, use `mix colony.reset` first.

### Load test

45. **The clients** are real WebSocket connections from the same VM. Each one joins as a
    player and moves 10 times each second near the nest. One of three puts scent. The scent
    of the demo mode is on, thus the 1,000 workers build a bridge and carry food.
46. **The bytes** are all the bytes that a client gets after the handshake, with the
    WebSocket frames and the channel headers.
