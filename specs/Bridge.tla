------------------------------- MODULE Bridge -------------------------------
(***************************************************************************)
(* The contract of a bridge: the lock rule, the support rule and the fall  *)
(* of plan 0001, section 4.3.                                              *)
(*                                                                         *)
(* The grid is the grid of lib/colony/grid.ex. A cell is an integer:       *)
(* row * Width + column. The rows with an odd number are half a cell to    *)
(* the right.                                                              *)
(*                                                                         *)
(* All the supports and the costs are in half units, thus they are         *)
(* integers: the bank support 8.0 of the plan is 16 here, the cost 1.0 is  *)
(* 2 and the cost 0.5 is 1.                                                *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
    Width,      \* the number of cells in a row
    NearRows,   \* the rows of the near bank
    GapRows,    \* the rows of the gap
    FarRows,    \* the rows of the far bank
    Bank,       \* the support of a bank cell that touches the gap
    Alone,      \* the cost of a body that is alone in its row
    Beside,     \* the cost of a body with a locked body beside it
    MaxLetGo    \* the model checker lets this number of workers go in one step, at most

ASSUME /\ Width \in Nat \ {0}
       /\ NearRows \in Nat \ {0}
       /\ GapRows \in Nat \ {0}
       /\ FarRows \in Nat \ {0}
       /\ Bank \in Nat
       /\ Alone \in Nat \ {0}
       /\ Beside \in Nat \ {0}
       /\ Beside <= Alone

VARIABLES
    workerBodies,   \* the gap cells that have a locked worker
    playerBodies    \* the gap cells that have a locked body of a player

bridge == <<workerBodies, playerBodies>>

-----------------------------------------------------------------------------
(* The grid *)

Rows == NearRows + GapRows + FarRows
Cells == 0 .. (Width * Rows - 1)
Row(c) == c \div Width
Col(c) == c % Width

NearCells == {c \in Cells : Row(c) < NearRows}
GapCells == {c \in Cells : Row(c) >= NearRows /\ Row(c) < NearRows + GapRows}
FarCells == {c \in Cells : Row(c) >= NearRows + GapRows}
BankCells == NearCells \cup FarCells

\* The row of a gap cell, from 1 at the near bank.
GapRow(c) == Row(c) - NearRows + 1

\* Each cell touches two cells in its row, two in the row before and two in the row after.
Touches(a, b) ==
    LET dr == Row(b) - Row(a)
        dc == Col(b) - Col(a)
        shift == Row(a) % 2
    IN  \/ dr = 0 /\ dc \in {-1, 1}
        \/ dr \in {-1, 1} /\ dc \in {shift - 1, shift}

\* The checker calculates these three functions one time: they do not change.
NeighborsOf ==
    [c \in Cells |->
        {d \in {c - 1, c + 1, c - Width - 1, c - Width, c - Width + 1,
                c + Width - 1, c + Width, c + Width + 1} \cap Cells : Touches(c, d)}]
BesideOf == [c \in Cells |-> {d \in NeighborsOf[c] : Row(d) = Row(c)}]
TouchesBank == [c \in Cells |-> NeighborsOf[c] \cap BankCells # {}]

Neighbors(c) == NeighborsOf[c]
BesideCells(c) == BesideOf[c]

-----------------------------------------------------------------------------
(* The support rule *)

Max(set) == CHOOSE m \in set : \A x \in set : x <= m

\* The cost of a body in the cell c, when S is the set of the locked cells.
Cost(S, c) == IF BesideCells(c) \cap S = {} THEN Alone ELSE Beside

\* One round of the rule: a body takes the highest support of the cells that it
\* touches, then it subtracts its cost. 0 is "no support".
Round(S, f) ==
    [c \in S |->
        LET cost == Cost(S, c)
            sources == (IF TouchesBank[c] THEN {Bank} ELSE {})
                           \cup {f[d] : d \in Neighbors(c) \cap S}
        IN  Max({0} \cup {s - cost : s \in sources})]

RECURSIVE Rounds(_, _)
Rounds(S, f) == LET g == Round(S, f) IN IF g = f THEN f ELSE Rounds(S, g)

\* The support of each cell of S. The rounds start with no support, thus all the
\* support comes from a bank.
Support(S) == Rounds(S, [c \in S |-> 0])

\* The bodies with no support fall. Then the bodies that lose their support fall also.
RECURSIVE Settle(_)
Settle(S) ==
    LET f == Support(S)
        weak == {c \in S : f[c] = 0}
    IN  IF weak = {} THEN S ELSE Settle(S \ weak)

-----------------------------------------------------------------------------
(* Where a free body can be *)

Walkable(S) == BankCells \cup S

\* The cells that a free body can get to from the near bank.
RECURSIVE Grow(_, _, _)
Grow(S, seen, front) ==
    LET more == (UNION {Neighbors(c) : c \in front} \cap Walkable(S)) \ seen
    IN  IF more = {} THEN seen ELSE Grow(S, seen \cup more, more)

Reach(S) == Grow(S, NearCells, NearCells)

-----------------------------------------------------------------------------
(* The lock rule *)

\* A body can lock into an empty gap cell only if its support will be more than 0.
\* A cell with support touches a bank cell or a locked body.
HasSupport(S, c) == c \in GapCells \ S /\ Support(S \cup {c})[c] > 0

\* The fast calculation of lib/colony/support.ex: the support of a new body in the
\* cell c, from the supports f of the bodies of S. A new body changes the cost only
\* of the bodies beside it.
Estimate(S, f, c) ==
    LET cost == IF BesideCells(c) \cap S = {} THEN Alone ELSE Beside
        gain(d) == IF d \in BesideCells(c) /\ BesideCells(d) \cap S = {}
                   THEN Alone - Beside ELSE 0
        sources == (IF TouchesBank[c] THEN {Bank} ELSE {})
                       \cup {f[d] + gain(d) : d \in Neighbors(c) \cap S}
    IN  Max({0} \cup {s - cost : s \in sources})

-----------------------------------------------------------------------------
(* The steps of a bridge *)

Bodies == workerBodies \cup playerBodies

BridgeInit == workerBodies = {} /\ playerBodies = {}

\* A worker locks into the cell c.
WorkerLock(c) ==
    /\ HasSupport(Bodies, c)
    /\ workerBodies' = workerBodies \cup {c}
    /\ UNCHANGED playerBodies

\* A player locks a body into the cell c.
PlayerLock(c) ==
    /\ HasSupport(Bodies, c)
    /\ playerBodies' = playerBodies \cup {c}
    /\ UNCHANGED workerBodies

\* The bodies that stay when the workers of `gone` let go.
After(gone) == Settle(Bodies \ gone)

\* Some locked workers let go. A locked body of a player does not let go.
LetGo(gone) ==
    /\ gone # {}
    /\ gone \subseteq workerBodies
    /\ workerBodies' = workerBodies \cap After(gone)
    /\ playerBodies' = playerBodies \cap After(gone)

\* The model of this module: all the free bodies come from the near bank. A free
\* body locks into a cell that touches the cell where the body is. (The module
\* Colony has the free bodies of the players, and has no such limit.)
\*
\* A bridge can have a state with no next step: only bodies of players, and no
\* cell where a lock is possible. Thus the configs have CHECK_DEADLOCK FALSE.
BridgeNext ==
    \/ \E c \in GapCells :
           /\ Neighbors(c) \cap Reach(Bodies) # {}
           /\ (WorkerLock(c) \/ PlayerLock(c))
    \/ \E gone \in SUBSET workerBodies : Cardinality(gone) <= MaxLetGo /\ LetGo(gone)

BridgeSpec == BridgeInit /\ [][BridgeNext]_bridge

-----------------------------------------------------------------------------
(* What is always true *)

BridgeTypeOK ==
    /\ workerBodies \subseteq GapCells
    /\ playerBodies \subseteq GapCells
    /\ workerBodies \cap playerBodies = {}

\* Each locked body has support.
AllSupported == \A c \in Bodies : Support(Bodies)[c] > 0

\* For each empty gap cell: what is true if a body locks there.
\*
\* 1. The fast calculation gives the same support as the full calculation.
\* 2. A new body never decreases the support of a body.
\* 3. Thus a new body never makes a body fall, and the server does not look for
\*    bodies that fall after a lock.
EstimateIsExact ==
    LET f == Support(Bodies)
    IN  \A c \in GapCells \ Bodies : Estimate(Bodies, f, c) = Support(Bodies \cup {c})[c]

SupportOnlyGrows ==
    LET f == Support(Bodies)
    IN  \A c \in GapCells \ Bodies :
            LET g == Support(Bodies \cup {c}) IN \A d \in Bodies : g[d] >= f[d]

LockKeepsAll ==
    \A c \in GapCells \ Bodies :
        LET g == Support(Bodies \cup {c}) IN g[c] > 0 => \A d \in Bodies \cup {c} : g[d] > 0

\* A locked body of a player goes away only when it has no support.
PlayerBodiesOnlyFall ==
    [][\A c \in playerBodies \ playerBodies' :
           Support(workerBodies' \cup playerBodies' \cup {c})[c] = 0]_bridge

\* A lock removes no body.
LockRemovesNothing ==
    [][Cardinality(workerBodies' \cup playerBodies') > Cardinality(Bodies)
           => Bodies \subseteq workerBodies' \cup playerBodies']_bridge

-----------------------------------------------------------------------------
(* The results of the plan, for a config with the numbers of the plan *)

\* The highest row of the gap that has a body.
TopRow == IF Bodies = {} THEN 0 ELSE Max({GapRow(c) : c \in Bodies})

\* "A bridge one cell wide stops at 7 rows."
StopsAtSeven == TopRow <= 7

\* This is false in some state if a bridge can get to row 7.
NeverRowSeven == TopRow < 7

\* This is false in some state if a free body can get to the far bank.
NeverAcross == Reach(Bodies) \cap FarCells = {}
=============================================================================
