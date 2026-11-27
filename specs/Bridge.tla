------------------------------- MODULE Bridge -------------------------------
(***************************************************************************)
(* The contract of a bridge across one river: the support rule of plan     *)
(* 0002, section 4.4, and the open cells of plan 0003, section 4.5.        *)
(* A lock is possible only where it helps.                                 *)
(*                                                                         *)
(* The module has one river. The near bank is the land before the river,   *)
(* and the far bank is the land after it. The world of the game has four   *)
(* rivers. Its rule for each river is this module.                         *)
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
    Costs,      \* the cost of a body in a line of 1, 2, ... bodies, as a sequence
    StartCols   \* the columns where the first body of the bridge can lock

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
       /\ StartCols \subseteq 0 .. Width - 1

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
(* The open cells: a lock is possible only where it helps *)

\* A body has support in an empty river cell if its support will be more than 0.
\* A cell with support touches a bank cell or a locked body.
HasSupport(S, c) == c \in GapCells \ S /\ Support(S \cup {c})[c] > 0

\* A bridge is complete when one of its bodies touches the far bank.
Complete(S) == \E c \in S : Neighbors(c) \cap FarCells # {}

\* The top row is the highest row of the bridge.
Top(S) == Max({Row(c) : c \in S})

\* The highest support of the bodies of S in a row.
TopSupport(S, row) ==
    LET f == Support(S)
    IN  Max({0} \cup {f[c] : c \in {d \in S : Row(d) = row}})

\* With no body in the river, the first row is open, in the start columns.
StartCells == {c \in GapCells : Row(c) = NearRows /\ Col(c) \in StartCols}

\* Forward first: the cells of the row after the top row that touch the bridge, and
\* where a body has support.
Ahead(S) ==
    {c \in GapCells \ S : Row(c) = Top(S) + 1 /\ Neighbors(c) \cap S # {} /\ HasSupport(S, c)}

\* Wider: the cells that touch the bridge, where a body has support and makes the
\* highest support of the top row larger.
Wider(S) ==
    {c \in GapCells \ S :
        /\ Neighbors(c) \cap S # {}
        /\ HasSupport(S, c)
        /\ TopSupport(S \cup {c}, Top(S)) > TopSupport(S, Top(S))}

\* The open cells. A complete bridge has none: it takes no more bodies.
Open(S) ==
    IF S = {} THEN StartCells
    ELSE IF Complete(S) THEN {}
    ELSE IF Ahead(S) # {} THEN Ahead(S)
    ELSE Wider(S)

BridgeInit == bodies = {}

\* A body locks into the cell c. A lock is possible only into an open cell. A worker
\* never locks: the body is the body of a player or of a helper.
LockBody(c) ==
    /\ c \in Open(bodies)
    /\ bodies' = bodies \cup {c}

\* A complete bridge has no next step. Thus the configs have CHECK_DEADLOCK FALSE.
BridgeNext == \E c \in GapCells : LockBody(c)

BridgeSpec == BridgeInit /\ [][BridgeNext]_bodies

\* A second model, for the checks of the support rule: a body locks into each cell
\* where it has support, open or not. This model has more structures than the open
\* cells permit. All the free bodies come from the near bank.
FreeLock(c) ==
    /\ HasSupport(bodies, c)
    /\ Neighbors(c) \cap Reach(bodies) # {}
    /\ bodies' = bodies \cup {c}

SupportSpec == BridgeInit /\ [][\E c \in GapCells : FreeLock(c)]_bodies

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

\* A body has support in each open cell.
OpenHasSupport == \A c \in Open(bodies) : HasSupport(bodies, c)

\* A free body from the near bank can get to a cell that touches each open cell.
OpenIsNear == \A c \in Open(bodies) : Neighbors(c) \cap Reach(bodies) # {}

\* One bridge for each river: all the bodies touch each other.
RECURSIVE Spread(_, _, _)
Spread(S, seen, front) ==
    LET more == (UNION {Neighbors(c) : c \in front} \cap S) \ seen
    IN  IF more = {} THEN seen ELSE Spread(S, seen \cup more, more)

OneBridge ==
    bodies = {} \/ (LET c == CHOOSE x \in bodies : TRUE IN Spread(bodies, {c}, {c}) = bodies)

\* No bridge stops before the far bank: a bridge with no open cell is complete.
NeverStuck == Open(bodies) = {} => (bodies # {} /\ Complete(bodies))

\* A complete bridge takes no more bodies.
CompleteTakesNoMore == [][Complete(bodies) => bodies' = bodies]_bodies

\* Forward first: while a body has support in the next row, each lock is in that row.
ForwardFirst ==
    [][(bodies # {} /\ Ahead(bodies) # {}) => \E c \in Ahead(bodies) : bodies' = bodies \cup {c}]_bodies

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

\* "A river of 9 rows needs 10 bodies": the first width of the table of plan 0003
\* where a bridge must be wider than one body.
NineRows == Straight(9)
TenBodies == Complete(bodies) => Cardinality(bodies) = 10

\* The same result with small numbers: with a bank support of 2, a bridge one body
\* wide stops at 1 row, and a river of 3 rows needs 4 bodies.
FourRiver == Straight(3)
FourBodies == Complete(bodies) => Cardinality(bodies) = 4
=============================================================================
