------------------------------ MODULE BridgeOpen ------------------------------
(***************************************************************************)
(* The open cells of plan 0003, section 4.5, in all the states of a small  *)
(* river: a lock is possible only into an open cell.                       *)
(*                                                                         *)
(* - One bridge for each river.                                            *)
(* - Forward first.                                                        *)
(* - Wider only when the bridge cannot go forward.                         *)
(* - A complete bridge takes no more bodies.                               *)
(* - No bridge stops before the far bank.                                  *)
(***************************************************************************)
EXTENDS Bridge
=============================================================================
