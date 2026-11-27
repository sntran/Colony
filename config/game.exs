import Config

# All the numbers of the game are in this file.
# Change a number here, then start the server again.
config :colony, :game,
  # Steps of the server each second.
  tick_rate: 10,

  # The grid. The rows go from the south to the north.
  width: 60,
  # The rows of land 0, where the nest is.
  near_rows: 14,
  # Each land after a river is this many rows deep at the widest place of the river.
  land_rows: 8,

  # The rivers, from the south to the north: {the least width, the largest width} in rows.
  # The width changes by 1 row or less from one column to the next.
  rivers: [{5, 7}, {9, 11}, {12, 14}, {16, 18}],

  # The nest: {row, column}.
  nest: {6, 30},

  # The piles of food. Pile `k` is on land `k`. These are the units of each pile.
  pile_units: [300, 400, 500, 600],
  pile_rows_from_river: 3,
  # Pile 1 is this many columns or less from the column of the nest.
  pile_first_columns: 10,
  # Each later pile is this many columns or more from each edge of the world.
  pile_edge_columns: 10,
  # A pile that no body can walk to loses 1 unit each time this many seconds go by.
  pile_loss_seconds: 1,
  # The loss stops at this many units.
  pile_least: 50,
  # A player takes food when the body is this many cells from the center of the pile, or
  # less. A body that walks on a cell beside the pile does not take food.
  food_touch: 0.75,
  # A player puts the food into the nest at this distance.
  nest_touch: 1.5,
  # The units that a player carries.
  player_food: 10,

  # The first body of a bridge locks this many columns or less from the column of the pile.
  # With no bridge, the workers wait at the edge of the land, below these cells.
  start_columns: 6,
  # While the workers can carry food, one worker of each `wait_part` waits at the crossing place.
  wait_part: 3,

  # Speed of a free body in cells each second.
  speed: 4.0,

  # Support rule. The cost of a locked body is 1 divided by the number of bodies in its
  # line in the row. `row_max` is the largest number that counts.
  bank_support: 8,
  row_max: 4,

  # Bodies. A lock uses one spare body: the player takes the body of the nearest worker.
  # A body that a player took cannot lock for this many seconds.
  takeover_seconds: 1,

  # Workers.
  workers: 30,
  workers_max: 200,
  # The nest makes 1 worker for each this many units of food.
  food_per_worker: 3,
  # With fewer spare bodies than `workers_low`, the nest makes 1 worker each `worker_seconds`.
  workers_low: 5,
  worker_seconds: 10,
  # A worker with no work stays this many cells or less from the nest.
  leash: 6,

  # Helpers: bodies that the server controls with the rules of a player.
  helpers: 0,
  # With `n` helpers, one helper locks each `helper_lock_seconds / n` seconds.
  helper_lock_seconds: 16,

  # Scent. A worker with food puts scent. It is a picture of the road: no rule reads it.
  scent_max: 100,
  scent_carry: 20,
  # Scent decreases by 1 each time this many seconds go by.
  scent_decay_seconds: 1,

  # Save.
  save_seconds: 30,
  save_file: "priv/data/world.bin",

  # The seed of the ground and of the river. Use nil for a random seed in a new world.
  seed: nil
