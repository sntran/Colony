------------------------------- MODULE Bridge -------------------------------
(***************************************************************************)
(* The contract of a bridge: the lock rule and the support rule of plan    *)
(* 0002, section 4.4. Each body beside a body helps.                       *)
(*                                                                         *)
(* The grid is the grid of lib/colony/grid.ex. A cell is an integer:       *)
(* row * Width + column. The rows with an odd number are half a cell to    *)
(* the right. The river has a width for each column.                       *)
(*                                                                         *)
(* All the supports and the costs are integers, as in the server: the      *)
(* bank support 8 is 96, and the costs 1, 1/2, 1/3 and 1/4 are 12, 6, 4    *)
(* and 3.                                                                  *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS
    Width,      \* the number of cells in a row
    NearRows,   \* the rows of the near bank
    River,      \* the width of the river in each column, as a sequence
    FarRows,    \* the rows of the far bank after the widest place of the river
    Bank,       \* the support of a bank cell that touches the river
    Costs       \* the cost of a body in a line of 1, 2, ... bodies, as a sequence

ASSUME /\ Width \in Nat \ {0}
       /\ NearRows \in Nat \ {0}
       /\ FarRows \in Nat \ {0}
       /\ Len(River) = Width
       /\ \A i \in 1 .. Width : River[i] \in Nat \ {0}
       /\ Bank \in Nat
       /\ Len(Costs) > 0
       /\ \A i \in 1 .. Len(Costs) : Costs[i] \in Nat \ {0}
       \* A longer line has a lower cost, or the same cost.
       /\ \A i \in 1 .. Len(Costs) - 1 : Costs[i + 1] <= Costs[i]

\* The set of the gap cells that have a locked body.
VARIABLE bodies

-----------------------------------------------------------------------------
(* The grid *)

Max(set) == CHOOSE m \in set : \A x \in set : x <= m

Rows == NearRows + Max({River[i] : i \in 1 .. Width}) + FarRows
Cells == 0 .. (Width * Rows - 1)
Row(c) == c \div Width
Col(c) == c % Width

NearCells == {c \in Cells : Row(c) < NearRows}
GapCells == {c \in Cells : Row(c) >= NearRows /\ Row(c) < NearRows + River[Col(c) + 1]}
FarCells == {c \in Cells : Row(c) >= NearRows + River[Col(c) + 1]}
BankCells == NearCells \cup FarCells

\* The row of a river cell, from 1 at the near bank.
GapRow(c) == Row(c) - NearRows + 1

\* Each cell touches two cells in its row, two in the row before and two in the row after.
Touches(a, b) ==
    LET dr == Row(b) - Row(a)
        dc == Col(b) - Col(a)
        shift == Row(a) % 2
    IN  \/ dr = 0 /\ dc \in {-1, 1}
        \/ dr \in {-1, 1} /\ dc \in {shift - 1, shift}

\* The checker calculates these functions one time: they do not change.
NeighborsOf ==
    [c \in Cells |->
        {d \in {c - 1, c + 1, c - Width - 1, c - Width, c - Width + 1,
                c + Width - 1, c + Width, c + Width + 1} \cap Cells : Touches(c, d)}]
TouchesBank == [c \in Cells |-> NeighborsOf[c] \cap BankCells # {}]

Neighbors(c) == NeighborsOf[c]

-----------------------------------------------------------------------------
(* The support rule *)

\* The number of bodies of S after the cell c in its row, with no hole, in one direction.
RECURSIVE Run(_, _, _)
Run(S, c, step) ==
    LET d == c + step
    IN  IF d \in S /\ d \in Cells /\ Row(d) = Row(c) THEN 1 + Run(S, d, step) ELSE 0

\* The number of bodies in the line that contains the cell c. A body is in c, or will be.
Line(S, c) == 1 + Run(S, c, -1) + Run(S, c, 1)

\* The cost of a body in the cell c. Each body beside a body makes the cost lower,
\* up to the last number of Costs.
Cost(S, c) ==
    LET n == Line(S, c)
    IN  Costs[IF n > Len(Costs) THEN Len(Costs) ELSE n]

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

-----------------------------------------------------------------------------
(* Where a free body can be *)

Walkable(S) == BankCells \cup S

\* The cells that a free body can get to on foot from the cells of `front`.
RECURSIVE Grow(_, _, _)
Grow(S, seen, front) ==
    LET more == (UNION {Neighbors(c) : c \in front} \cap Walkable(S)) \ seen
    IN  IF more = {} THEN seen ELSE Grow(S, seen \cup more, more)

ReachFrom(S, start) == Grow(S, start, start)
Reach(S) == ReachFrom(S, NearCells)

-----------------------------------------------------------------------------
(* The lock rule *)

\* A body can lock into an empty river cell only if its support will be more than 0.
\* A cell with support touches a bank cell or a locked body.
HasSupport(S, c) == c \in GapCells \ S /\ Support(S \cup {c})[c] > 0

BridgeInit == bodies = {}

\* A body locks into the cell c. A worker never locks: the body is the body of a
\* player or of a helper.
LockBody(c) ==
    /\ HasSupport(bodies, c)
    /\ bodies' = bodies \cup {c}

\* The model of this module: all the free bodies come from the near bank. A free
\* body locks into a cell that touches the cell where the body is. (The module
\* Colony has the free bodies of the players.)
\*
\* A bridge can have a state with no next step: no cell where a lock is possible.
\* Thus the configs have CHECK_DEADLOCK FALSE.
BridgeNext == \E c \in GapCells : Neighbors(c) \cap Reach(bodies) # {} /\ LockBody(c)

BridgeSpec == BridgeInit /\ [][BridgeNext]_bodies

-----------------------------------------------------------------------------
(* What is always true *)

BridgeTypeOK == bodies \subseteq GapCells

\* Each locked body has support.
AllSupported == \A c \in bodies : Support(bodies)[c] > 0

\* A new body never decreases the support of a body.
SupportOnlyGrows ==
    LET f == Support(bodies)
    IN  \A c \in GapCells \ bodies :
            LET g == Support(bodies \cup {c}) IN \A d \in bodies : g[d] >= f[d]

\* Thus a new body never makes a body fall, and the server does not look for
\* bodies that fall after a lock.
LockKeepsAll ==
    \A c \in GapCells \ bodies :
        LET g == Support(bodies \cup {c}) IN g[c] > 0 => \A d \in bodies \cup {c} : g[d] > 0

\* A body beside a body helps: the new body makes the cost of each body of its line
\* lower, or the same.
BodyBesideHelps ==
    \A c \in GapCells \ bodies :
        \A d \in bodies : Cost(bodies \cup {c}, d) <= Cost(bodies, d)

\* A locked body stays: no step removes it.
BodiesStay == [][bodies \subseteq bodies']_bodies

-----------------------------------------------------------------------------
(* The results of the plan, for a config with the numbers of the plan *)

\* The highest row of the river that has a body.
TopRow == IF bodies = {} THEN 0 ELSE Max({GapRow(c) : c \in bodies})

\* "A bridge one body wide stops at 7 rows." For a grid that is one cell wide.
StopsAtSeven == TopRow <= 7

\* This is false in some state if a bridge can get to row 7.
NeverRowSeven == TopRow < 7

\* The support of each river cell when bodies are in all of them. SupportOnlyGrows
\* tells that no bridge gives a body more support than this.
FullSupport == Support(GapCells)

\* With bodies in all the river cells, the rows 1 to n have support and the row
\* n + 1 has none. The river of the config is long: the far bank gives no support
\* to these rows. For a grid that is 2 or 3 cells wide, this tells that a bridge
\* of that width stops at row n.
FullStopsAt(n) ==
    \A c \in GapCells :
        /\ GapRow(c) <= n => FullSupport[c] > 0
        /\ GapRow(c) = n + 1 => FullSupport[c] = 0

TwoWideStopsAtFifteen == FullStopsAt(15)
ThreeWideStopsAtTwentyThree == FullStopsAt(23)

\* This is false in some state if a free body can get to the far bank.
NeverAcross == Reach(bodies) \cap FarCells = {}

-----------------------------------------------------------------------------
(* Values for the configs. A config file cannot have a sequence. *)

PlanCosts == <<12, 6, 4, 3>>
Straight(rows) == [i \in 1 .. Width |-> rows]
SmallRiver == Straight(3)
BentRiver == <<2, 3, 3, 2>>
LongRiver == Straight(50)
OneBody == Cardinality(bodies) <= 1
=============================================================================
