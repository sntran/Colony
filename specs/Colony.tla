------------------------------- MODULE Colony -------------------------------
(***************************************************************************)
(* The contract between a player and the world of plan 0004.               *)
(*                                                                         *)
(* The module Bridge has the support rule and the open cells. This module  *)
(* adds the free body of each player and the workers of the colony: where  *)
(* a body can go, when it can lock, and which body the player gets at a    *)
(* lock. The colony has carriers and spare bodies. A lock uses one spare   *)
(* body and never a carrier. The number of carriers never decreases. A     *)
(* player who carries food cannot lock. At the crossing, the nest moves.   *)
(* A worker never locks.                                                   *)
(*                                                                         *)
(* A test monitors the real world (lib/colony/world.ex) against this       *)
(* module: each message to the world is an action here, and the reply of   *)
(* the world is the last parameter `r` of the action.                      *)
(***************************************************************************)
EXTENDS Bridge

CONSTANTS
    Players,    \* the names of the players
    Nest,       \* the cell of the nest at the start
    Workers,    \* the largest number of spare bodies at the start
    MaxSpare,   \* the largest number of spare bodies
    Carriers,   \* the largest number of carriers at the start
    MaxCarriers \* the largest number of carriers

ASSUME /\ Nest \in NearCells
       /\ Workers \in 0 .. MaxSpare
       /\ Carriers \in 0 .. MaxCarriers

VARIABLES
    life,       \* for each player: "out" (not in the world) or "alive"
    at,         \* for each player: the cell of the free body; the nest if there is none
    rest,       \* for each player: TRUE while the body cannot lock
    food,       \* for each player: TRUE while the body carries food
    spare,      \* the number of spare bodies
    carriers,   \* the number of carriers
    nest        \* the cell of the nest

vars == <<bodies, life, at, rest, food, spare, carriers, nest>>

\* In a reply, this is in the place of a cell when there is no cell.
NoCell == -1

Init ==
    /\ BridgeInit
    /\ nest = Nest
    /\ life = [p \in Players |-> "out"]
    /\ at = [p \in Players |-> Nest]
    /\ rest = [p \in Players |-> FALSE]
    /\ food = [p \in Players |-> FALSE]
    /\ spare \in 0 .. Workers
    /\ carriers \in 0 .. Carriers

\* The cells where the nest can be after the lock into the cell c. At the crossing, the
\* nest moves to the foot of the bridge: a cell of the near bank. The contract does not
\* say which cell.
NestsAfter(c) ==
    IF Complete(bodies \cup {c}) /\ ~Complete(bodies) THEN NearCells ELSE {nest}

\* The body of a player who is not in the world is at the nest.
AtAfter(n) == [q \in Players |-> IF life[q] = "out" THEN n ELSE at[q]]

-----------------------------------------------------------------------------
(* The messages of a player. The reply of the world is `r`. *)

\* A player comes into the world and gets a body at the nest. This body does not use
\* a spare body.
Join(p, r) ==
    /\ p \in Players
    /\ life[p] = "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, food, spare, carriers, nest>>

\* A player goes out of the world. The locked bodies of the player stay.
Leave(p, r) ==
    /\ p \in Players
    /\ life[p] # "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "out"]
    /\ at' = [at EXCEPT ![p] = nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    \* The food of a body that goes out of the world is lost.
    /\ food' = [food EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, spare, carriers, nest>>

\* A free body goes only to a cell that touches its cell, and only on bank cells
\* and on locked bodies.
CanMove(p, c) ==
    /\ life[p] = "alive"
    /\ c \in Neighbors(at[p]) \cup {at[p]}
    /\ c \in Walkable(bodies)

\* A player moves the body to the cell c. The world says "no" if the body cannot go there.
Move(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanMove(p, c)
       THEN r = "ok" /\ at' = [at EXCEPT ![p] = c]
       ELSE r = "no" /\ UNCHANGED at
    /\ UNCHANGED <<bodies, life, rest, food, spare, carriers, nest>>

\* A free body can lock into an open cell that touches the cell where the body is,
\* and only if the colony has a spare body. A body that a player took a moment before
\* cannot lock. A body that carries food cannot lock.
CanPlayerLock(p, c) ==
    /\ life[p] = "alive"
    /\ ~rest[p]
    /\ ~food[p]
    /\ c \in Neighbors(at[p])
    /\ c \in Open(bodies)
    /\ spare > 0

\* A player locks the body into the cell c. The lock uses one spare body, never a
\* carrier: the player takes the body of a spare body, and the reply has the cell of
\* that body. The contract does not have the places of the workers, thus it permits
\* each cell that a free body can get to on foot from the locked body. A player always
\* has a body.
Lock(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanPlayerLock(p, c)
       THEN /\ bodies' = bodies \cup {c}
            /\ spare' = spare - 1
            /\ \E d \in ReachFrom(bodies \cup {c}, {c}), n \in NestsAfter(c) :
                  /\ r = <<"ok", d>>
                  /\ nest' = n
                  /\ at' = [AtAfter(n) EXCEPT ![p] = d]
                  /\ rest' = [rest EXCEPT ![p] = TRUE]
            /\ UNCHANGED <<life, food, carriers>>
       ELSE /\ r = <<"error", NoCell>>
            /\ UNCHANGED vars

\* A player asks for the locked bodies.
Look(r) ==
    /\ r = bodies
    /\ UNCHANGED vars

\* A player asks for the number of spare bodies.
Spare(r) ==
    /\ r = spare
    /\ UNCHANGED vars

\* A player asks for the state of a free body.
Where(p, r) ==
    /\ p \in Players
    /\ r = <<life[p], at[p]>>
    /\ UNCHANGED vars

-----------------------------------------------------------------------------
(* The events of the world *)

\* The body that a player took can lock now.
Rested(p) ==
    /\ p \in Players
    /\ rest[p]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, life, at, food, spare, carriers, nest>>

\* The body of a player touches a pile and takes food.
FoodTaken(p) ==
    /\ p \in Players
    /\ life[p] = "alive"
    /\ ~food[p]
    /\ food' = [food EXCEPT ![p] = TRUE]
    /\ UNCHANGED <<bodies, life, at, rest, spare, carriers, nest>>

\* The body of a player puts its food into the nest.
FoodGiven(p) ==
    /\ p \in Players
    /\ food[p]
    /\ food' = [food EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, life, at, rest, spare, carriers, nest>>

\* A helper locks into the cell c. A helper obeys the rules of a player: the cell is
\* open, and the lock uses one spare body. The contract does not have the free bodies
\* of the helpers.
HelperLocked(c) ==
    /\ spare > 0
    /\ LockBody(c)
    /\ spare' = spare - 1
    /\ \E n \in NestsAfter(c) : nest' = n /\ at' = AtAfter(n)
    /\ UNCHANGED <<life, rest, food, carriers>>

\* The nest makes a spare body.
WorkerMade ==
    /\ spare < MaxSpare
    /\ spare' = spare + 1
    /\ UNCHANGED <<bodies, life, at, rest, food, carriers, nest>>

\* The colony gets a carrier: at a crossing.
CarrierMade ==
    /\ carriers < MaxCarriers
    /\ carriers' = carriers + 1
    /\ UNCHANGED <<bodies, life, at, rest, food, spare, nest>>

-----------------------------------------------------------------------------

\* The replies of a lock are tuples. The other replies are strings. The checker
\* cannot compare a tuple with a string, thus each action has its own replies.
LockReplies == {<<"error", NoCell>>} \cup {<<"ok", d>> : d \in Cells}

Next ==
    \/ \E p \in Players :
          \/ \E r \in {"ok", "no"} :
                \/ Join(p, r)
                \/ Leave(p, r)
                \/ \E c \in Cells : Move(p, c, r)
          \/ \E c \in Cells, r \in LockReplies : Lock(p, c, r)
          \/ Rested(p)
          \/ FoodTaken(p)
          \/ FoodGiven(p)
    \/ \E c \in GapCells : HelperLocked(c)
    \/ WorkerMade
    \/ CarrierMade

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* What is always true *)

TypeOK ==
    /\ BridgeTypeOK
    /\ life \in [Players -> {"out", "alive"}]
    /\ at \in [Players -> Cells]
    /\ rest \in [Players -> BOOLEAN]
    /\ food \in [Players -> BOOLEAN]
    /\ spare \in 0 .. MaxSpare
    /\ carriers \in 0 .. MaxCarriers
    /\ nest \in NearCells

\* A free body is never in the river with no locked body below it.
FreeBodiesOnGround == \A p \in Players : life[p] = "alive" => at[p] \in Walkable(bodies)

\* A player who is not in the world is not on a cell, and has no body that rests.
NoBodyNoPlace == \A p \in Players : life[p] # "alive" => at[p] = nest /\ ~rest[p] /\ ~food[p]

\* A locked body stays, also when players come and go.
AllBodiesStay == [][bodies \subseteq bodies']_vars

\* A lock uses one spare body. The spare bodies are the workers: thus each new locked
\* body is the body of a player or of a helper, and a worker never locks.
LockUsesSpare ==
    [][bodies' # bodies =>
           /\ spare > 0
           /\ spare' = spare - 1
           /\ Cardinality(bodies') = Cardinality(bodies) + 1]_vars

\* A lock is possible only into an open cell. Thus a complete bridge takes no more
\* bodies.
LockOnlyOpen == [][bodies' # bodies => \E c \in Open(bodies) : bodies' = bodies \cup {c}]_vars

\* The number of carriers never decreases, and a lock never uses a carrier.
CarriersNeverDecrease == [][carriers' >= carriers]_vars
LockNeverUsesCarrier == [][bodies' # bodies => carriers' = carriers]_vars

\* A player who carries food cannot lock. Only a lock makes a body rest.
NoLockWithFood == [][\A p \in Players : (food[p] /\ ~rest[p]) => ~rest'[p]]_vars

\* The nest moves only at a crossing.
NestMovesAtCrossing == [][nest' # nest => Complete(bodies') /\ ~Complete(bodies)]_vars

\* A player always has a body: a lock does not take the player out of the world.
PlayerKeepsBody ==
    [][\A p \in Players : (life[p] = "alive" /\ bodies' # bodies) => life'[p] = "alive"]_vars

\* A player who comes into the world starts at the nest.
NewBodyAtNest ==
    [][\A p \in Players : life[p] # "alive" /\ life'[p] = "alive" => at'[p] = nest]_vars

\* A body that a player took rests first: the player cannot lock two times in one moment.
TakenBodyRests ==
    [][\A p \in Players :
           (life[p] = "alive" /\ life'[p] = "alive" /\ bodies' # bodies /\ at'[p] # at[p]) => rest'[p]]_vars

-----------------------------------------------------------------------------
(* Values for the configs *)

TwoColumns == <<3, 3>>
SixColumns == <<4, 4, 4, 4, 4, 4>>
=============================================================================
