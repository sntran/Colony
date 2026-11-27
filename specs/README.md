# The TLA+ contracts of the game

A contract is a TLA+ module that tells what the world can do. The checker and the
monitor come from [accord](https://github.com/sntran/accord/tree/feat/native-tla-checker):
a TLA+ model checker in Elixir. Java is not necessary.

I use each contract in two ways:

1. **The checker looks at all the states of a small model.** It finds a state where a
   rule is false, if there is one.
2. **The tests follow the real world against the contract.** Each change of the real
   world must be a step that the contract permits.

The contracts have the rules of [plan 0002](../docs/plans/0002-players-are-the-bridge.md):
only players and helpers lock, a locked body stays, and each body beside a body helps.

## The files

| File | Contents |
|---|---|
| `Bridge.tla` | The river, the lock rule and the support rule (plan 0002, sections 4.1, 4.2 and 4.4). |
| `Bridge.cfg` | A river 3 cells wide and 3 rows. The checker looks at all the 147 states. |
| `BridgeWide.tla`, `.cfg` | A river 4 cells wide. Its columns are 2, 3, 3 and 2 rows. Lines of 4 bodies are possible. 711 states. |
| `BridgeOneWide.tla`, `.cfg` | The numbers of the plan on a grid one cell wide: "a bridge one body wide stops at 7 rows". |
| `BridgeTwoWide.tla`, `.cfg` | The numbers of the plan on a grid two cells wide: "two bodies wide stops at 15 rows". |
| `BridgeThreeWide.tla`, `.cfg` | The numbers of the plan on a grid three cells wide: "three bodies wide stops at 23 rows". |
| `Colony.tla` | The contract between a player and the world: join, move, lock, the body of a worker, the new body at the nest. |
| `Colony.cfg` | A river 2 cells wide and 3 rows, with one player. The checker looks at all the 433 states. |
| `ColonyPlay.cfg` | A river 6 cells wide and 3 rows, with two players. The monitor test makes a real world from it. |

The supports and the costs are the integers of `lib/colony/support.ex`: the bank support 8
is 96, and the costs 1, 1/2, 1/3 and 1/4 are 12, 6, 4 and 3. The small models use a bank
support of 2 (24) or 1.5 (18). Thus a bridge one body wide stops there after 1 row, as it
does after 7 rows with the numbers of the plan.

A cell is the same integer as in `lib/colony/grid.ex`: `row * Width + column`. `River` is
a sequence: the width of the river in each column.

## What the contracts say

Always true (the checker looks at each state):

- `AllSupported`: each locked body has support.
- `LockKeepsAll` and `SupportOnlyGrows`: a new body never decreases the support of a
  body. Thus no body falls after a lock, and the server does not look for one.
- `BodyBesideHelps`: a new body never increases the cost of a body.
- `FreeBodiesOnGround`: a free body is never in the river with no locked body below it.
- `NoBodyNoPlace`: a player with no body has no place of its own. The contract keeps the
  nest as its place, and the new body starts there.

True for each step:

- `BodiesStay` and `AllBodiesStay`: no step removes a locked body.
- `BodyLostByLock`: a player loses a body only by a lock.
- `TakenBodyRests`: after a lock that gives the body of a worker, the player cannot lock
  before the rest is at its end.
- `NewBodyAtNest`: a player who got no worker starts again at the nest.

The results of the plan:

- `StopsAtSeven`: with the numbers of the plan, a bridge one body wide has no body after
  row 7. A test also makes sure that the checker finds a state with a body in row 7: it
  checks `NeverRowSeven` and expects a violation.
- `TwoWideStopsAtFifteen` and `ThreeWideStopsAtTwentyThree`: with a body in each cell of
  a river of 50 rows, the bodies of rows 1 to 15 (or 23) have support, and the bodies of
  the next row do not. More bodies never decrease a support. Thus no bridge of that width
  gets farther.

The contracts do not have the workers. A worker never locks, thus a worker changes no
value of a contract. The lock reply of `Colony.tla` says only this about workers: the
player gets the body of a worker at a cell where a body can be, or the player gets no body.

## How to check

```sh
mix colony.contracts          # all the modules, about 20 seconds
mix colony.contracts Bridge   # one module
mix test                      # the same checks, and the tests with the real world
```

`mix accord.check --no-deadlock --extra specs/Bridge.tla` checks one module with the task
of accord. It needs `--no-deadlock` for the bridge modules: the task does not read
`CHECK_DEADLOCK FALSE` from the config file.

## The tests with the real world

- `test/contract_monitor_test.exs` puts `Accord.Spec.Monitor` between a test player and a
  real world (`Colony.World`) with the numbers of `ColonyPlay.cfg`. Two players send 220
  random messages in each of 4 runs: moves, locks, join and leave. One helper builds, and
  5 workers are the spare bodies. Each message, each reply and each event must be a step
  of `Colony.tla`. After each message the monitor compares the locked bodies and the body
  of each player with the contract.
- The same file gives the world a wrong bank support. The monitor reports the first wrong
  lock and blames the server.
- `test/contract_check_test.exs` runs 4 helpers on the grid of the game, with the river
  of a seed. Each lock of a helper must be a step of the contract, and the bodies of the
  world must be the bodies of the contract after each lock.

## When you change a rule

Change the contract first. Run `mix colony.contracts`. Then change the code and run
`mix test`. If the numbers of `config/game.exs` change, the tests of "the numbers of the
game config" use the new numbers. Change the config files of `BridgeOneWide`,
`BridgeTwoWide` and `BridgeThreeWide` by hand.
