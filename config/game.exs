import Config

# All the numbers of the game are in this file.
# Change a number here, then start the server again.
config :colony, :game,
  # Steps of the server each second.
  tick_rate: 10,

  # The grid. Rows are parallel to the banks.
  width: 60,
  near_rows: 14,
  # The rows of the far bank after the widest place of the river.
  far_rows: 14,

  # The river. Its width changes along its length, from `river_min` to `river_max` rows.
  # The narrowest place is `river_min` rows wide or one row more. It is not more than
  # `river_narrow_columns` columns from the nest.
  river_min: 5,
  river_max: 16,
  river_narrow_columns: 6,

  # The nest: {row, column}. Row 0 is the row farthest from the river on the near bank.
  nest: {6, 30},

  # The piles of food. There is one pile at a time, on the far bank.
  pile_units: 300,
  pile_rows_from_river: 3,
  # The first pile is across the narrowest place. The next piles are across places with
  # these widths. After that, the places are random.
  pile_widths: [9, 12, 14, 16],
  # A new pile is this many columns or more from each complete bridge, if that is possible.
  pile_bridge_columns: 8,
  # From the first lock to the first food, a pile loses 1 unit each time this many seconds go by.
  pile_loss_seconds: 1,
  # A worker goes to the pile when the pile is not more than this many cells away.
  food_radius: 6,
  # A player gets the message of the pile when the body is this many cells from it, or less.
  food_touch: 2.0,

  # Speed of a free body in cells each second.
  speed: 4.0,

  # Support rule. The cost of a locked body is 1 divided by the number of bodies in its
  # line in the row. `row_max` is the largest number that counts.
  bank_support: 8,
  row_max: 4,

  # Bodies. After a lock, a player takes the body of the nearest free worker.
  # A body that a player took cannot lock for this many seconds.
  takeover_seconds: 1,
  # With no free worker, the player gets a new body at the nest after this many seconds.
  respawn_seconds: 3,

  # Workers.
  workers: 30,
  workers_max: 200,
  # The nest makes 1 worker for each this many units of food.
  food_per_worker: 10,
  # With fewer free workers than `workers_low`, the nest makes 1 worker each `worker_seconds`.
  workers_low: 5,
  worker_seconds: 10,
  # A worker with no scent near stays this many cells or less from scent or from the nest.
  leash: 6,

  # Helpers: bodies that the server controls with the rules of a player.
  helpers: 0,
  # A helper locks one time each this many seconds at most.
  helper_lock_seconds: 16,
  # The demo mode has this many helpers.
  demo_helpers: 4,

  # Scent.
  scent_max: 100,
  scent_player: 100,
  scent_carry: 20,
  # Scent decreases by 1 each time this many seconds go by.
  scent_decay_seconds: 1,

  # Save.
  save_seconds: 30,
  save_file: "priv/data/world.bin",

  # The seed of the ground and of the river. Use nil for a random seed in a new world.
  seed: nil
