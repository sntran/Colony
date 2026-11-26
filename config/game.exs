import Config

# All the numbers of the game are in this file.
# Change a number here, then start the server again.
config :colony, :game,
  # Steps of the server each second.
  tick_rate: 10,

  # The grid. Rows are parallel to the banks.
  width: 60,
  near_rows: 14,
  gap_rows: 12,
  far_rows: 14,

  # The nest: {row, column}. Row 0 is the row farthest from the gap on the near bank.
  nest: {6, 30},

  # The food pile: the number of rows from the gap on the far bank, and the column.
  food_rows_from_gap: 4,
  food_column: 30,
  food_units: 500,
  # The pile becomes full again this many seconds after it becomes empty. Use nil for never.
  food_refill_seconds: 60,
  # A worker goes to the food when the food is not more than this many cells away.
  food_radius: 6,

  # Speed of a free body in cells each second.
  speed: 4.0,

  # Support rule.
  bank_support: 8.0,
  cost_alone: 1.0,
  cost_beside: 0.5,

  # Seconds from a lock to the new body of the player.
  respawn_seconds: 1,

  # Scent.
  scent_max: 100,
  scent_player: 100,
  scent_carry: 20,
  # Scent decreases by 1 each time this many seconds go by.
  scent_decay_seconds: 1,

  # Workers.
  workers: 200,
  # A worker with no scent near stays this many cells or less from scent or from the nest.
  leash: 6,
  # A locked worker that no free body uses lets go after this many seconds.
  let_go_seconds: 20,

  # Save.
  save_seconds: 30,
  save_file: "priv/data/world.bin",

  # The seed of the ground. Use nil for a random seed in a new world.
  seed: nil
