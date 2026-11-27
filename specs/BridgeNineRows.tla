---------------------------- MODULE BridgeNineRows ----------------------------
(***************************************************************************)
(* A result of plan 0003, section 4.5: "A river of 9 rows needs 10         *)
(* bodies."                                                                *)
(*                                                                         *)
(* A bridge one body wide stops at 7 rows. With the open cells, a bridge   *)
(* goes forward for 7 rows, gets one body beside a body, and goes forward  *)
(* again. The config has the numbers of the plan and a river of 9 rows.    *)
(* The checker looks at all the bridges that the open cells permit: each   *)
(* complete bridge has 10 bodies, and no bridge stops before the far bank. *)
(***************************************************************************)
EXTENDS Bridge
=============================================================================
