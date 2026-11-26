------------------------------- MODULE Colony -------------------------------
(***************************************************************************)
(* The contract between a player and the world of plan 0002.               *)
(*                                                                         *)
(* The module Bridge has the lock rule and the support rule. This module   *)
(* adds the free body of each player: where it can go, when it can lock,   *)
(* and which body the player gets after a lock.                            *)
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
    at,         \* for each player: the cell of the free body; the nest if there is none
    rest        \* for each player: TRUE while the body cannot lock

vars == <<bodies, life, at, rest>>

\* In a reply, this is in the place of a cell when there is no cell.
NoCell == -1

Init ==
    /\ BridgeInit
    /\ life = [p \in Players |-> "out"]
    /\ at = [p \in Players |-> Nest]
    /\ rest = [p \in Players |-> FALSE]

-----------------------------------------------------------------------------
(* The messages of a player. The reply of the world is `r`. *)

\* A player comes into the world and gets a body at the nest.
Join(p, r) ==
    /\ p \in Players
    /\ life[p] = "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED bodies

\* A player goes out of the world. The locked bodies of the player stay.
Leave(p, r) ==
    /\ p \in Players
    /\ life[p] # "out"
    /\ r = "ok"
    /\ life' = [life EXCEPT ![p] = "out"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED bodies

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
    /\ UNCHANGED <<bodies, life, rest>>

\* A free body can lock into an empty river cell that touches the cell where the body
\* is. A body that a player took a moment before cannot lock.
CanPlayerLock(p, c) ==
    /\ life[p] = "alive"
    /\ ~rest[p]
    /\ c \in Neighbors(at[p])
    /\ HasSupport(bodies, c)

\* A player locks the body into the cell c. Then the player takes the body of a free
\* worker: the reply has the cell of that body. The contract does not have the
\* workers, thus it permits each cell that a free body can get to on foot from the
\* locked body. With no free worker, the reply has no cell, and the player has no body.
Lock(p, c, r) ==
    /\ p \in Players
    /\ c \in Cells
    /\ IF CanPlayerLock(p, c)
       THEN /\ bodies' = bodies \cup {c}
            /\ \/ \E d \in ReachFrom(bodies \cup {c}, {c}) :
                     /\ r = <<"ok", d>>
                     /\ at' = [at EXCEPT ![p] = d]
                     /\ rest' = [rest EXCEPT ![p] = TRUE]
                     /\ UNCHANGED life
               \/ /\ r = <<"ok", NoCell>>
                  /\ life' = [life EXCEPT ![p] = "dead"]
                  /\ at' = [at EXCEPT ![p] = Nest]
                  /\ UNCHANGED rest
       ELSE /\ r = <<"error", NoCell>>
            /\ UNCHANGED vars

\* A player asks for the locked bodies.
Look(r) ==
    /\ r = bodies
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
    /\ UNCHANGED <<bodies, life, at>>

\* The world gives a player a new body at the nest.
Respawn(p) ==
    /\ p \in Players
    /\ life[p] = "dead"
    /\ life' = [life EXCEPT ![p] = "alive"]
    /\ at' = [at EXCEPT ![p] = Nest]
    /\ rest' = [rest EXCEPT ![p] = FALSE]
    /\ UNCHANGED bodies

\* A helper locks into the cell c. The contract does not have the free bodies of the
\* helpers.
HelperLocked(c) ==
    /\ LockBody(c)
    /\ UNCHANGED <<life, at, rest>>

-----------------------------------------------------------------------------

\* The replies of a lock are tuples. The other replies are strings. The checker
\* cannot compare a tuple with a string, thus each action has its own replies.
LockReplies == {<<"error", NoCell>>} \cup {<<"ok", d>> : d \in Cells \cup {NoCell}}

Next ==
    \/ \E p \in Players :
          \/ \E r \in {"ok", "no"} :
                \/ Join(p, r)
                \/ Leave(p, r)
                \/ \E c \in Cells : Move(p, c, r)
          \/ \E c \in Cells, r \in LockReplies : Lock(p, c, r)
          \/ Rested(p)
          \/ Respawn(p)
    \/ \E c \in GapCells : HelperLocked(c)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* What is always true *)

TypeOK ==
    /\ BridgeTypeOK
    /\ life \in [Players -> {"out", "alive", "dead"}]
    /\ at \in [Players -> Cells]
    /\ rest \in [Players -> BOOLEAN]

\* A free body is never in the river with no locked body below it.
FreeBodiesOnGround == \A p \in Players : life[p] = "alive" => at[p] \in Walkable(bodies)

\* A player with no body is not on a cell, and a body that rests is the body of a player.
NoBodyNoPlace == \A p \in Players : life[p] # "alive" => at[p] = Nest /\ ~rest[p]

\* A locked body stays, also when players come and go.
AllBodiesStay == [][bodies \subseteq bodies']_vars

\* A player loses a body only by a lock.
BodyLostByLock ==
    [][\A p \in Players :
           life[p] = "alive" /\ life'[p] = "dead" => Cardinality(bodies') = Cardinality(bodies) + 1]_vars

\* A new body after a time with no body starts at the nest.
NewBodyAtNest ==
    [][\A p \in Players : life[p] # "alive" /\ life'[p] = "alive" => at'[p] = Nest]_vars

\* A body that a player took rests first: the player cannot lock two times in one moment.
TakenBodyRests ==
    [][\A p \in Players :
           (life[p] = "alive" /\ life'[p] = "alive" /\ bodies' # bodies /\ at'[p] # at[p]) => rest'[p]]_vars

-----------------------------------------------------------------------------
(* Values for the configs *)

TwoColumns == <<3, 3>>
SixColumns == <<3, 3, 3, 3, 3, 3>>
=============================================================================
