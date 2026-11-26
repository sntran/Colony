# The checks of the large TLA+ models take minutes. Run them with `mix test --include slow`.
ExUnit.start(exclude: [:slow])
