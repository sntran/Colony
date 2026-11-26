---------------------------- MODULE BridgeTwoWide ----------------------------
(***************************************************************************)
(* A result of plan 0002: "A bridge two bodies wide stops at 15 rows."     *)
(*                                                                         *)
(* The config has the numbers of the plan and a grid that is 2 cells      *)
(* wide, with a river of 50 rows. With bodies in all the river cells, only *)
(* the rows 1 to 15 have support. A new body never decreases a support   *)
(* (the module Bridge checks this in all the states of small models), thus *)
(* no bridge of this width gives a body in a later row support.            *)
(***************************************************************************)
EXTENDS Bridge
=============================================================================
