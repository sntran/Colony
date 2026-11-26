------------------------------- MODULE Colony -------------------------------
(***************************************************************************)
(* The contract between a player and the world of plan 0001.               *)
(*                                                                         *)
(* The module Bridge has the lock rule, the support rule and the fall.     *)
(* This module adds the free body of each player: where it can go, when    *)
(* it can lock, and when the player gets a new body.                       *)
(*                                                                         *)
(* A test monitors the real world (lib/colony/world.ex) against this       *)
(* module: each message to the world is an action here, and the reply of   *)
(* the world is the last parameter `r` of the action.                      *)
(***************************************************************************)
EXTENDS Bridge

CONSTANTS
    Players,    \* the names of the players
    Nest        \* the cell of the nest

ASSUME Nest \in NearCells

VARIABLES
    life,       \* for each player: "out" (not in the world), "alive" or "dead"
    at          \* for each player: the cell of the free body; the nest if there is none

vars == <<workerBodies, playerBodies, life, at>>

Init ==
    /\ BridgeInit
    /\ life = [p \in Players |-> "out"]
    /\ at = [p \in Players |-> Nest]

-----------------------------------------------------------------------------
(* The messages of a player. The reply of the world is `r`. *)

\* A player comes into the world and gets a body at the nest.
Join(p, r) ==
    /\ p \in Players
    /\ life[p] = "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ UNCHANGED bridge

\* A player goes out of the world. The locked bodies of the player stay.
Leave(p, r) ==
    /\ p \in Players
    /\ life[p] # "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "out"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ UNCHANGED bridge

\* A free body goes only to a cell that touches its cell, and only on bank cells
\* and on locked bodies.
CanMove(p, c) ==
    /\ life[p] = "alive"
    /\ c \in Neighbors(at[p]) \cup {at[p]}
    /\ c \in Walkable(Bodies)

\* A player moves the body to the cell c. The world says "no" if the body cannot go there.
Move(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanMove(p, c)
       THEN r = "ok" /\ at' = [at EXCEPT ![p] = c]
       ELSE r = "no" /\ UNCHANGED at
    /\ UNCHANGED <<bridge, life>>

\* A free body can lock into an empty gap cell that touches the cell where the body is.
CanPlayerLock(p, c) ==
    /\ life[p] = "alive"
    /\ c \in Neighbors(at[p])
    /\ HasSupport(Bodies, c)

\* A player locks the body into the cell c. Then the player has no free body.
Lock(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanPlayerLock(p, c)
       THEN /\ r = "ok"
            /\ PlayerLock(c)
            /\ life' = [life EXCEPT ![p] = "dead"]
            /\ at' = [at EXCEPT ![p] = Nest]
       ELSE /\ r = "error"
            /\ UNCHANGED vars

\* A player asks for the locked bodies.
Look(r) ==
    /\ r = <<workerBodies, playerBodies>>
    /\ UNCHANGED vars

\* A player asks for the state of a free body.
Where(p, r) ==
    /\ p \in Players
    /\ r = <<life[p], at[p]>>
    /\ UNCHANGED vars

-----------------------------------------------------------------------------
(* The events of the world *)

\* The world gives a player a new body at the nest.
Respawn(p) ==
    /\ p \in Players
    /\ life[p] = "dead"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ UNCHANGED bridge

\* A worker locks into the cell c.
WorkerLocked(c) ==
    /\ WorkerLock(c)
    /\ UNCHANGED <<life, at>>

\* Some locked workers let go. The bodies with no support fall. A free body on a
\* body that goes away falls also.
WorkersLetGo(gone) ==
    /\ LetGo(gone)
    /\ LET falls(p) == life[p] = "alive" /\ at[p] \in GapCells \ After(gone)
       IN  /\ life' = [p \in Players |-> IF falls(p) THEN "dead" ELSE life[p]]
           /\ at' = [p \in Players |-> IF falls(p) THEN Nest ELSE at[p]]

-----------------------------------------------------------------------------

Next ==
    \/ \E p \in Players :
          \/ \E r \in {"ok", "no", "error"} :
                \/ Join(p, r)
                \/ Leave(p, r)
                \/ \E c \in Cells : Move(p, c, r) \/ Lock(p, c, r)
          \/ Respawn(p)
    \/ \E c \in GapCells : WorkerLocked(c)
    \/ \E gone \in SUBSET workerBodies : Cardinality(gone) <= MaxLetGo /\ WorkersLetGo(gone)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* What is always true *)

TypeOK ==
    /\ BridgeTypeOK
    /\ life \in [Players -> {"out", "alive", "dead"}]
    /\ at \in [Players -> Cells]

\* A free body is never in the gap with no locked body below it.
FreeBodiesOnGround == \A p \in Players : life[p] = "alive" => at[p] \in Walkable(Bodies)

\* A player loses a body only by a lock or by a fall.
BodyLostByLockOrFall ==
    [][\A p \in Players :
           life[p] = "alive" /\ life'[p] = "dead" =>
               \/ Cardinality(playerBodies') = Cardinality(playerBodies) + 1
               \/ at[p] \notin Walkable(workerBodies' \cup playerBodies')]_vars

\* A new body starts at the nest.
NewBodyAtNest ==
    [][\A p \in Players : life[p] # "alive" /\ life'[p] = "alive" => at'[p] = Nest]_vars

=============================================================================
