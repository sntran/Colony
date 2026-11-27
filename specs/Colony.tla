------------------------------- MODULE Colony -------------------------------
(***************************************************************************)
(* The contract between a player and the world of plan 0003.               *)
(*                                                                         *)
(* The module Bridge has the support rule and the open cells. This module  *)
(* adds the free body of each player and the spare bodies of the colony:   *)
(* where a body can go, when it can lock, and which body the player gets   *)
(* at a lock. A lock uses one spare body. A worker never locks.            *)
(*                                                                         *)
(* A test monitors the real world (lib/colony/world.ex) against this       *)
(* module: each message to the world is an action here, and the reply of   *)
(* the world is the last parameter `r` of the action.                      *)
(***************************************************************************)
EXTENDS Bridge

CONSTANTS
    Players,    \* the names of the players
    Nest,       \* the cell of the nest
    Workers,    \* the largest number of workers at the start
    MaxSpare    \* the largest number of spare bodies

ASSUME /\ Nest \in NearCells
       /\ Workers \in 0 .. MaxSpare

VARIABLES
    life,       \* for each player: "out" (not in the world) or "alive"
    at,         \* for each player: the cell of the free body; the nest if there is none
    rest,       \* for each player: TRUE while the body cannot lock
    spare       \* the number of spare bodies: the workers of the colony

vars == <<bodies, life, at, rest, spare>>

\* In a reply, this is in the place of a cell when there is no cell.
NoCell == -1

Init ==
    /\ BridgeInit
    /\ life = [p \in Players |-> "out"]
    /\ at = [p \in Players |-> Nest]
    /\ rest = [p \in Players |-> FALSE]
    /\ spare \in 0 .. Workers

-----------------------------------------------------------------------------
(* The messages of a player. The reply of the world is `r`. *)

\* A player comes into the world and gets a body at the nest. This body does not use
\* a spare body.
Join(p, r) ==
    /\ p \in Players
    /\ life[p] = "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, spare>>

\* A player goes out of the world. The locked bodies of the player stay.
Leave(p, r) ==
    /\ p \in Players
    /\ life[p] # "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "out"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED <<bodies, spare>>

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
    /\ UNCHANGED <<bodies, life, rest, spare>>

\* A free body can lock into an open cell that touches the cell where the body is,
\* and only if the colony has a spare body. A body that a player took a moment before
\* cannot lock.
CanPlayerLock(p, c) ==
    /\ life[p] = "alive"
    /\ ~rest[p]
    /\ c \in Neighbors(at[p])
    /\ c \in Open(bodies)
    /\ spare > 0

\* A player locks the body into the cell c. The lock uses one spare body: the player
\* takes the body of a worker, and the reply has the cell of that body. The contract
\* does not have the places of the workers, thus it permits each cell that a free
\* body can get to on foot from the locked body. A player always has a body.
Lock(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanPlayerLock(p, c)
       THEN /\ bodies' = bodies \cup {c}
            /\ spare' = spare - 1
            /\ \E d \in ReachFrom(bodies \cup {c}, {c}) :
                  /\ r = <<"ok", d>>
                  /\ at' = [at EXCEPT ![p] = d]
                  /\ rest' = [rest EXCEPT ![p] = TRUE]
            /\ UNCHANGED life
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
    /\ UNCHANGED <<bodies, life, at, spare>>

\* A helper locks into the cell c. A helper obeys the rules of a player: the cell is
\* open, and the lock uses one spare body. The contract does not have the free bodies
\* of the helpers.
HelperLocked(c) ==
    /\ spare > 0
    /\ LockBody(c)
    /\ spare' = spare - 1
    /\ UNCHANGED <<life, at, rest>>

\* The nest makes a worker: one more spare body.
WorkerMade ==
    /\ spare < MaxSpare
    /\ spare' = spare + 1
    /\ UNCHANGED <<bodies, life, at, rest>>

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
    \/ \E c \in GapCells : HelperLocked(c)
    \/ WorkerMade

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* What is always true *)

TypeOK ==
    /\ BridgeTypeOK
    /\ life \in [Players -> {"out", "alive"}]
    /\ at \in [Players -> Cells]
    /\ rest \in [Players -> BOOLEAN]
    /\ spare \in 0 .. MaxSpare

\* A free body is never in the river with no locked body below it.
FreeBodiesOnGround == \A p \in Players : life[p] = "alive" => at[p] \in Walkable(bodies)

\* A player who is not in the world is not on a cell, and has no body that rests.
NoBodyNoPlace == \A p \in Players : life[p] # "alive" => at[p] = Nest /\ ~rest[p]

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

\* A player always has a body: a lock does not take the player out of the world.
PlayerKeepsBody ==
    [][\A p \in Players : (life[p] = "alive" /\ bodies' # bodies) => life'[p] = "alive"]_vars

\* A player who comes into the world starts at the nest.
NewBodyAtNest ==
    [][\A p \in Players : life[p] # "alive" /\ life'[p] = "alive" => at'[p] = Nest]_vars

\* A body that a player took rests first: the player cannot lock two times in one moment.
TakenBodyRests ==
    [][\A p \in Players :
           (life[p] = "alive" /\ life'[p] = "alive" /\ bodies' # bodies /\ at'[p] # at[p]) => rest'[p]]_vars

-----------------------------------------------------------------------------
(* Values for the configs *)

TwoColumns == <<3, 3>>
SixColumns == <<4, 4, 4, 4, 4, 4>>
=============================================================================
