# The TLA+ contracts of the game

A contract is a TLA+ module that tells what the world can do. The checker and the
monitor come from [accord](https://github.com/sntran/accord/tree/feat/native-tla-checker):
a TLA+ model checker in Elixir. Java is not necessary.

I use each contract in two ways:

1. **The checker looks at all the states of a small model.** It finds a state where a
   rule is false, if there is one.
2. **The tests follow the real world against the contract.** Each change of the real
   world must be a step that the contract permits.

The contracts have the rules of [plan 0003](../docs/plans/0003-the-crossing.md) and of
[plan 0004](../docs/plans/0004-the-road-north.md): a lock is possible only into an open
cell, a lock uses one spare body and never a carrier, the number of carriers never
decreases, a player who carries food cannot lock, a complete bridge takes no more bodies,
the nest moves only at a crossing, and a worker never locks. The support rule is the rule
of plan 0002.

## The files

| File | Contents |
|---|---|
| `Bridge.tla` | One river: the support rule (plan 0002, section 4.4) and the open cells (plan 0003, section 4.5). |
| `Bridge.cfg` | The support rule in all the structures of a river 3 cells wide and 3 rows. A body locks into each cell where it has support, open or not. 147 states. |
| `BridgeWide.tla`, `.cfg` | The same on a river 4 cells wide. Its columns are 2, 3, 3 and 2 rows. Lines of 4 bodies are possible. 711 states. |
| `BridgeOpen.tla`, `.cfg` | The open cells on a river 4 cells wide and 3 rows: a body locks only into an open cell. 29 states. |
| `BridgeOneWide.tla`, `.cfg` | The numbers of the plan on a grid one cell wide: "a bridge one body wide stops at 7 rows". |
| `BridgeTwoWide.tla`, `.cfg` | The numbers of the plan on a grid two cells wide: "two bodies wide stops at 15 rows". |
| `BridgeThreeWide.tla`, `.cfg` | The numbers of the plan on a grid three cells wide: "three bodies wide stops at 23 rows". |
| `BridgeNineRows.tla`, `.cfg` | The numbers of the plan on a river of 9 rows: each complete bridge has 10 bodies. 632 states. |
| `Colony.tla` | The contract between a player and the world: join, move, lock, the spare bodies, the carriers, the food of a player, the nest, the body of a worker. |
| `Colony.cfg` | A river 2 cells wide and 3 rows, with one player, 0 to 2 spare bodies and 0 or 1 carrier at the start. 1,728 states. |
| `ColonyPlay.cfg` | A river 6 cells wide and 4 rows, with two players. The monitor test makes a real world from it. |

The supports and the costs are the integers of `lib/colony/support.ex`: the land support 8
is 96, and the costs 1, 1/2, 1/3 and 1/4 are 12, 6, 4 and 3. The small models use a
support of 2 (24) or 1.5 (18). Thus a bridge one body wide stops there after 1 row, as it
does after 7 rows with the numbers of the plan.

A cell is the same integer as in `lib/colony/grid.ex`: `row * Width + column`. `River` is
a sequence: the width of the river in each column. The module has one river: the rows
before it are the near bank, and the rows after it are the far bank. The world of the
game has no end, and the rule for each river is this module. `StartCols` has the
columns where the first body of a bridge can lock.

## What the contracts say

The open cells, as the server calculates them (`Colony.Support.open/5`):

- `StartCells`: with no body in the river, the first row is open, in the start columns.
- `Ahead`: forward first. The cells of the row after the top row that touch the bridge,
  where a body has support.
- `Wider`: if no cell is ahead, the cells that touch the bridge, where a body has support
  and makes the highest support of the top row larger.
- `Complete`: a bridge that touches the far bank has no open cell.

Always true (the checker looks at each state):

- `AllSupported`: each locked body has support.
- `LockKeepsAll` and `SupportOnlyGrows`: a new body never decreases the support of a
  body. Thus no body falls after a lock, and the server does not look for one.
- `BodyBesideHelps`: a new body never increases the cost of a body.
- `OpenHasSupport`: a body has support in each open cell.
- `OpenIsNear`: a free body can get to a cell that touches each open cell.
- `OneBridge`: all the bodies of a river touch each other.
- `NeverStuck`: a bridge with no open cell is complete. No bridge stops before the far
  bank.
- `FreeBodiesOnGround`: a free body is never in the river with no locked body below it.
- `NoBodyNoPlace`: a player who is not in the world has no place of its own, no body
  that rests and no food.
- `TypeOK`: the number of spare bodies is never less than 0, and a player in the world
  always has a body.

True for each step:

- `BodiesStay` and `AllBodiesStay`: no step removes a locked body.
- `ForwardFirst`: while a cell is ahead, each lock is into a cell that is ahead.
- `CompleteTakesNoMore`: a complete bridge gets no more bodies.
- `LockOnlyOpen`: each new body is in an open cell.
- `LockUsesSpare`: each lock uses one spare body. Thus each new locked body is the body
  of a player or of a helper, and a worker never locks.
- `LockNeverUsesCarrier`: a lock does not change the number of carriers.
- `CarriersNeverDecrease`: no step decreases the number of carriers.
- `NoLockWithFood`: a player who carries food cannot lock.
- `NestMovesAtCrossing`: the nest moves only at the step that makes a bridge complete.
- `PlayerKeepsBody`: a lock does not take the player out of the world.
- `TakenBodyRests`: after a lock, the player cannot lock before the rest is at its end.
- `NewBodyAtNest`: a player who comes into the world starts at the nest.

The results of the plans:

- `StopsAtSeven`: with the numbers of the plan, a bridge one body wide has no body after
  row 7. A test also makes sure that the checker finds a state with a body in row 7: it
  checks `NeverRowSeven` and expects a violation.
- `TwoWideStopsAtFifteen` and `ThreeWideStopsAtTwentyThree`: with a body in each cell of
  a river of 50 rows, the bodies of rows 1 to 15 (or 23) have support, and the bodies of
  the next row do not. More bodies never decrease a support. Thus no bridge of that width
  gets farther with the support of one land.
- `TenBodies`: on a river of 9 rows, each complete bridge has 10 bodies. This is the
  first width of the table of plan 0003, section 4.5, where a bridge must get wider.
- `FourBodies`: the same result with small numbers, in `BridgeOpen`.

The contracts do not have the places of the workers. A worker never locks, thus a worker
changes no locked body. The contract has the number of spare bodies and of carriers: a
lock subtracts one spare body, the event `WorkerMade` adds one, and the event
`CarrierMade` adds one carrier. The events `FoodTaken` and `FoodGiven` are the food of a
player. The lock reply says this about workers: the player gets the body of a spare body
at a cell that a body can get to on foot from the locked body.

## How to check

```sh
mix colony.contracts          # all the modules, about 2 minutes
mix colony.contracts Bridge   # one module
mix test                      # the same checks, and the tests with the real world
```

`BridgeNineRows` needs 80 seconds or more. The other modules together need 30 seconds.

`mix accord.check --no-deadlock --extra specs/Bridge.tla` checks one module with the task
of accord. It needs `--no-deadlock` for the bridge modules: the task does not read
`CHECK_DEADLOCK FALSE` from the config file.

## The tests with the real world

- `test/contract_monitor_test.exs` puts `Accord.Spec.Monitor` between a test player and a
  real world (`Colony.World`) with the numbers of `ColonyPlay.cfg`. Two players send up
  to 220 random messages in each of 4 runs: moves, locks, join and leave. One helper
  builds. The contract has one river: a run stops at the crossing, because the world then
  gets the next river. Each message, each reply and each event must be a
  step of `Colony.tla`. After each message the monitor compares the locked bodies, the
  number of spare bodies and the body of each player with the contract.
- The same file gives the world a wrong land support. The monitor reports the first lock
  into a cell that is not open in the contract, and blames the server.
- `test/contract_check_test.exs` makes the contract of river 1 of the game from a real
  world: each lock of a player into an open cell is a step, and a lock into a cell that
  is not open is not a step. Then 4 helpers build across river 1 and river 2: each lock
  must be a step of the contract of its river, and the bodies of the world must be the
  bodies of the contract.
- `test/contract_plan_test.exs` checks `BridgeNineRows`. It is in a file of its own: it
  runs at the same time as the other tests.

## When you change a rule

Change the contract first. Run `mix colony.contracts`. Then change the code and run
`mix test`. If the numbers of `config/game.exs` change, change the config files of
`BridgeOneWide`, `BridgeTwoWide`, `BridgeThreeWide` and `BridgeNineRows` by hand.
