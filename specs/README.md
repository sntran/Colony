# The TLA+ contracts of the game

A contract is a TLA+ module that tells what the world can do. The checker and the
monitor come from [accord](https://github.com/sntran/accord/tree/feat/native-tla-checker):
a TLA+ model checker in Elixir. Java is not necessary.

I use each contract in two ways:

1. **The checker looks at all the states of a small model.** It finds a state where a
   rule is false, if there is one.
2. **The tests follow the real world against the contract.** Each change of the real
   world must be a step that the contract permits.

## The files

| File | Contents |
|---|---|
| `Bridge.tla` | The lock rule, the support rule and the fall (plan 0001, section 4.3). |
| `Bridge.cfg` | A gap 2 cells wide and 3 rows. The checker looks at all the 593 states. |
| `BridgeOneWide.tla`, `.cfg` | The numbers of the plan on a grid one cell wide: "a bridge one cell wide stops at 7 rows". |
| `BridgeWide.tla`, `.cfg` | A gap 3 cells wide and 3 rows. This check takes minutes. |
| `Colony.tla` | The contract between a player and the world: join, move, lock, new body, fall. |
| `Colony.cfg` | The small gap with one player. The checker looks at all the 6,094 states. |
| `ColonyPlay.cfg` | The small gap with two players. The monitor test makes a real world from it. |

All the supports and the costs are in half units, thus they are integers: the bank
support 8.0 is 16, the cost 1.0 is 2 and the cost 0.5 is 1.

A cell is the same integer as in `lib/colony/grid.ex`: `row * Width + column`.

## What the contracts say

Always true (the checker looks at each state):

- `AllSupported`: each locked body has support.
- `EstimateIsExact`: the fast calculation of the support in `lib/colony/support.ex` gives
  the same number as the full calculation.
- `LockKeepsAll` and `SupportOnlyGrows`: a new body never makes a body fall. Thus the
  server does not look for bodies that fall after a lock.
- `FreeBodiesOnGround`: a free body is never in the gap with no locked body below it.

True for each step:

- `PlayerBodiesOnlyFall`: a locked body of a player goes away only when it has no support.
- `LockRemovesNothing`: a lock removes no body.
- `BodyLostByLockOrFall`: a player loses a body only by a lock or by a fall.
- `NewBodyAtNest`: a new body starts at the nest.

The results of the plan:

- `StopsAtSeven`: with the numbers of the plan, a bridge one cell wide has no body after
  row 7. The checker also finds a state with a body in row 7.
- A test follows the 24 locks of a bridge two cells wide across the 12 rows.

## How to check

```sh
mix colony.contracts          # Bridge, BridgeOneWide and Colony
mix colony.contracts --all    # and BridgeWide
mix test                      # the fast checks and the tests with the real world
mix test --include slow       # all the checks
```

`mix accord.check --no-deadlock --extra specs/Bridge.tla` checks one module with the task
of accord. It needs `--no-deadlock` for the bridge modules: the task does not read
`CHECK_DEADLOCK FALSE` from the config file.

## The tests with the real world

- `test/contract_monitor_test.exs` puts `Accord.Spec.Monitor` between a test player and a
  real world (`Colony.World`) with the numbers of `ColonyPlay.cfg`. Two players send
  random messages: moves, locks, scent, join and leave. Three workers build, let go and
  fall. Each message and each event must be a step of `Colony.tla`. After each message the
  monitor compares the locked bodies and the bodies of the players.
- `test/contract_check_test.exs` runs 200 workers on the grid of the game. Each lock of a
  worker and each time that workers let go must be a step of the contract.

## When you change a rule

Change the contract first. Run `mix colony.contracts`. Then change the code and run
`mix test`. If the numbers of `config/game.exs` change, the test of "the numbers of the
game config" uses the new numbers. Change `BridgeOneWide.cfg` by hand.
