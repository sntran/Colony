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
  # The width changes by 1 row or less from one column to the next. The world has no end:
  # each river after the list has the widths of the last river of the list. No river is
  # wider than 27 rows.
  rivers: [{5, 7}, {9, 11}, {12, 14}, {16, 18}, {19, 21}, {22, 24}, {25, 27}],
  # The world has rivers as far as this many rivers after the newest pile.
  rivers_ahead: 2,

  # The nest: {row, column}. At each crossing, the nest moves to the foot of the new
  # bridge: this many rows south of the first body of that bridge.
  nest: {6, 30},
  nest_rows: 3,

  # The table of the open cells (test/open_test.exs, `mix colony.table`): the bodies of a
  # bridge across a river of each width. "Best" always takes the open cell with the
  # largest gain. "Random" is the highest of 200 runs that take a random open cell.
  bridge_best: %{
    5 => 5,
    6 => 6,
    7 => 7,
    8 => 8,
    9 => 10,
    10 => 13,
    11 => 16,
    12 => 19,
    13 => 22,
    14 => 25,
    15 => 28,
    16 => 31,
    17 => 36,
    18 => 41,
    19 => 46,
    20 => 51,
    21 => 56,
    22 => 61,
    23 => 66,
    24 => 73,
    25 => 80,
    26 => 87,
    27 => 94
  },
  bridge_random: %{
    5 => 5,
    6 => 6,
    7 => 7,
    8 => 8,
    9 => 10,
    10 => 13,
    11 => 19,
    12 => 23,
    13 => 28,
    14 => 34,
    15 => 39,
    16 => 43,
    17 => 48,
    18 => 54,
    19 => 58,
    20 => 64,
    21 => 69,
    22 => 74,
    23 => 80,
    24 => 85,
    25 => 89,
    26 => 94,
    27 => 100
  },

  # The piles of food. Pile `k` is on land `k`, and it pays for the bridge across river
  # `k + 1`. With R and B of the table for the largest width of that river:
  # the size of the pile is food_per_body * pile_factor * R, and the pile does not lose
  # units below food_per_body * pile_least_factor * B.
  pile_factor: 1.5,
  pile_least_factor: 1.1,
  pile_rows_from_river: 3,
  # Pile 1 is this many columns or less from the column of the nest.
  pile_first_columns: 10,
  # Each later pile is this many columns or less from the pile before it, and this many
  # columns or more from each edge of the world.
  pile_shift_columns: 12,
  pile_edge_columns: 10,
  # A pile that no body can walk to loses 1 unit each time this many seconds go by.
  pile_loss_seconds: 1,
  # A player takes food when the body is this many cells from the center of the pile, or
  # less. A body that walks on a cell beside the pile does not take food.
  food_touch: 0.75,
  # A player puts the food into the nest at this distance.
  nest_touch: 1.5,
  # The units that a player carries.
  player_food: 10,

  # The first body of a bridge locks this many columns or less from the column of the pile.
  # With no bridge, the spare bodies wait at the edge of the land, below these cells.
  start_columns: 6,

  # Speed of a free body in cells each second.
  speed: 4.0,

  # Support rule. The cost of a locked body is 1 divided by the number of bodies in its
  # line in the row. `row_max` is the largest number that counts.
  bank_support: 8,
  row_max: 4,

  # Bodies. A lock uses one spare body: the player takes the body of the nearest spare body.
  # A body that a player took cannot lock for this many seconds.
  takeover_seconds: 1,

  # Workers. A carrier carries food: a lock never uses a carrier. A spare body waits at the
  # crossing place: a lock uses one.
  carriers: 12,
  # The colony gets this many carriers at each crossing, at the new nest.
  carriers_per_crossing: 8,
  carriers_max: 150,
  spare: 10,
  spare_max: 200,
  # The nest makes 1 spare body for each this many units of food.
  food_per_body: 5,
  # With fewer spare bodies than `spare_low` and no pile with food that a body can walk
  # to, the nest makes 1 spare body each `spare_seconds`.
  spare_low: 5,
  spare_seconds: 10,
  # A worker with no work stays this many cells or less from the nest.
  leash: 6,

  # Helpers: bodies that the server controls with the rules of a player.
  helpers: 0,
  # With `n` helpers, one helper locks each `helper_lock_seconds / n` seconds.
  helper_lock_seconds: 16,

  # Scent. A carrier with food puts scent. It is a picture of the road: no rule reads it.
  scent_max: 100,
  scent_carry: 20,
  # Scent decreases by 1 each time this many seconds go by.
  scent_decay_seconds: 1,

  # Save.
  save_seconds: 30,
  save_file: "priv/data/world.bin",

  # The seed of the ground and of the river. Use nil for a random seed in a new world.
  seed: nil
