(* GRISP Kernel – Coq Mechanization Skeleton (v0.55) *)
(* Based on Formal SOS rules.                                      *)

Require Import List.
Require Import String.
Require Import ZArith.
Require Import Bool.
Require Import Program.
Require Import FunctionalExtensionality.
Require Import OrderedType.
Require Import FMapFacts.
Require Import FMapList.
Require Import Psatz.

Import ListNotations.

(* ---------------------------------------------------------------------- *)
(* 1. Core Types                                                          *)
(* ---------------------------------------------------------------------- *)

Module Type ID.
  Parameter t : Type.
  Parameter type_name : t -> string.
  Parameter seq_num : t -> Z.
  Parameter eq_dec : forall x y : t, {x = y} + {x <> y}.
  Parameter compare : t -> t -> comparison.
  Axiom compare_spec : forall x y, CompareSpec (x = y) (compare x y = Lt) (compare x y = Gt) (compare x y).
  Axiom compare_type_name_seq : forall x y,
    compare x y = match (String.compare (type_name x) (type_name y)) with
                  | Eq => Z.compare (seq_num x) (seq_num y)
                  | c => c
                  end.
End ID.

Module Type VALUE.
  Inductive value :=
  | IntVal (z : Z)
  | FixedVal (scale : nat) (scaled : Z)
  | BoolVal (b : bool)
  | StringVal (s : string)
  | IdentVal (id : ID.t)
  | ListVal (l : list value)
  | MapVal (m : list (value * value)).
  Axiom value_eq_dec : forall x y : value, {x = y} + {x <> y}.
End VALUE.

(* We'll use concrete modules for simplicity in this skeleton. *)
Module ID <: ID.
  Definition t := (string * Z)%type.
  Definition type_name (x : t) := fst x.
  Definition seq_num (x : t) := snd x.
  Definition eq_dec := String.eq_dec.
  Definition compare (x y : t) :=
    match String.compare (fst x) (fst y) with
    | Eq => Z.compare (snd x) (snd y)
    | c => c
    end.
  Lemma compare_spec : forall x y, CompareSpec (x = y) (compare x y = Lt) (compare x y = Gt) (compare x y).
  Proof.
    intros. unfold compare.
    destruct (String.compare_spec (fst x) (fst y)).
    - subst. destruct (Z.compare_spec (snd x) (snd y)); constructor; auto.
    - constructor; auto.
    - constructor; auto.
  Qed.
  Lemma compare_type_name_seq : forall x y,
    compare x y = match String.compare (fst x) (fst y) with
                  | Eq => Z.compare (snd x) (snd y)
                  | c => c
                  end.
  Proof. reflexivity. Qed.
End ID.

Module Value <: VALUE.
  Inductive value :=
  | IntVal (z : Z)
  | FixedVal (scale : nat) (scaled : Z)
  | BoolVal (b : bool)
  | StringVal (s : string)
  | IdentVal (id : ID.t)
  | ListVal (l : list value)
  | MapVal (m : list (value * value)).
  Lemma value_eq_dec : forall x y : value, {x = y} + {x <> y}.
  Proof.
    decide equality.
    - apply ID.eq_dec.
    - apply string_dec.
    - apply bool_dec.
    - apply Z.eq_dec.
  Qed.
End Value.

Module Field <: OrderedType.
  Definition t := string.
  Definition eq := @eq string.
  Definition lt := String.lt.
  Lemma eq_equiv : Equivalence eq. Proof. apply eq_equivalence. Qed.
  Lemma lt_trans : Transitive lt. Proof. apply String.lt_trans. Qed.
  Lemma lt_not_eq : forall x y, lt x y -> ~ eq x y. Proof. apply String.lt_not_eq. Qed.
  Lemma compare : forall x y, Compare lt eq x y.
  Proof.
    intros. destruct (String.compare_spec x y).
    - apply EQ; auto.
    - apply LT; auto.
    - apply GT; auto.
  Qed.
End Field.

Module Type GRAPH.
  Record node := {
    node_id : ID.t;
    node_type : string;
    node_fields : Map.t Field.t value
  }.
  Record edge := {
    edge_id : ID.t;
    edge_type : string;
    edge_src : ID.t;
    edge_tgt : ID.t;
    edge_fields : Map.t Field.t value
  }.
  Record t := {
    nodes : Map.t ID.t node;
    edges : Map.t ID.t edge
  }.
End GRAPH.

Module Graph <: GRAPH.
  Import Map.
  Include Graph.
End Graph.

Module Type COUNTERS.
  Record t := {
    tick_counter : Z;
    seq_counter : Map.t string Z;        (* per type *)
    type_extent_version : Map.t string Z; (* per type *)
    element_version : Map.t ID.t Z;       (* per element *)
    adjacency_version : Map.t (ID.t * string * dir) Z (* (node, edge_type, dir) *)
  }.
  (* dir: in or out *)
  Inductive dir := In | Out.
End COUNTERS.

Module Counters <: COUNTERS.
  Include Counters.
End Counters.

Module Type MATCH.
  Record t := {
    key : (string * list (string * Value.value));  (* rule_id, sorted bindings *)
    bindings : Map.t string Value.value;
    read_set : list (string * Value.value);        (* simplified for now *)
    age : Z
  }.
End MATCH.

Module Match <: MATCH.
  Include Match.
End Match.

Module Type ACTION.
  Inductive primitive :=
  | CreateNode (x : ID.t) (typ : string) (fields : Map.t Field.t Value.value)
  | CreateEdge (x : ID.t) (typ : string) (src : ID.t) (tgt : ID.t) (fields : Map.t Field.t Value.value)
  | UpdateField (target : ID.t) (field : string) (new_val : Value.value)
  | DeleteEdge (e : ID.t)
  | DeleteNode (x : ID.t)
  | EmitEvent (event_type : string) (payload : list Value.value).
  Definition alpha := list primitive. (* Canonical Action Trace *)
  Definition handle := nat.
  Definition alpha_with_handles := list (handle * primitive).
End ACTION.

Module Action <: ACTION.
  Include Action.
End Action.

Module Type CONFIG.
  Record t := {
    G : Graph.t;
    C : Counters.t;
    M_prev : Map.t Match.key Z;
    Rejected : Map.t Match.key unit
  }.
End CONFIG.

Module Config <: CONFIG.
  Include Config.
End Config.

Module Type IR.
  Record rule := {
    rule_id : string;
    base_priority : Z;
    priority_scale : Z;
    fairness_scale : Z;
    pattern : list (string * string); (* (var, type) *)
    constraints : list (string * Value.value); (* simplified *)
    let_bindings : list (string * Value.value);
    actions : list Action.primitive
  }.
  Definition t := list rule.
End IR.

Module IR <: IR.
  Include IR.
End IR.

(* ---------------------------------------------------------------------- *)
(* 2. ORDER_CANONICAL (total order)                                       *)
(* ---------------------------------------------------------------------- *)

Module OrderCanonical.
  Import Value.
  Import ID.

  (* order_key : value -> list (nat * ...) *)
  Fixpoint order_key (v : value) : list (nat * (list (nat * ...))) :=
    match v with
    | IntVal z => [ (0, z) ]
    | FixedVal scale scaled => [ (1, scale, scaled) ]
    | BoolVal b => [ (2, if b then 1 else 0) ]
    | StringVal s => [ (3, s) ]
    | IdentVal id => [ (4, ID.type_name id, ID.seq_num id) ]
    | ListVal l => [ (5, map order_key l) ]
    | MapVal m => [ (6, sort (fun x y => compare_order_key (fst x) (fst y)) (map (fun p => (order_key (fst p), order_key (snd p))) m)) ]
    end.

  (* compare_order_key : value -> value -> comparison *)
  Definition compare_order_key (v1 v2 : value) : comparison :=
    let k1 := order_key v1 in
    let k2 := order_key v2 in
    compare_order_key_list k1 k2.

  (* Axiom: order_key is injective and preserves comparison *)
  Axiom order_key_inj : forall v1 v2, order_key v1 = order_key v2 -> v1 = v2.
  Axiom order_key_compare : forall v1 v2, compare_order_key v1 v2 = compare_order_key_list (order_key v1) (order_key v2).

  (* Total order theorem *)
  Theorem total_order : forall v1 v2, compare_order_key v1 v2 = Eq \/ compare_order_key v1 v2 = Lt \/ compare_order_key v1 v2 = Gt.
  Proof.
    (* By construction of compare_order_key_list which is total *)
    admit. (* Placeholder: prove by induction on structure *)
  Qed.

  Theorem antisym : forall v1 v2, compare_order_key v1 v2 = Eq -> v1 = v2.
  Proof.
    intros. apply order_key_inj. 
    (* compare_order_key_list_eq implies order_key equal *)
    admit.
  Qed.

  Theorem transitive : forall v1 v2 v3,
    compare_order_key v1 v2 = Lt ->
    compare_order_key v2 v3 = Lt ->
    compare_order_key v1 v3 = Lt.
  Proof.
    admit.
  Qed.

  (* The total order is also used for identifiers, lists, and maps. *)
  (* We lift it to match_key and other structures *)
End OrderCanonical.

(* ---------------------------------------------------------------------- *)
(* 3. Helper Functions (Axiomatized for Skeleton)                         *)
(* ---------------------------------------------------------------------- *)

Module Helpers.

  Import Graph.
  Import Counters.
  Import Match.
  Import Action.
  Import Config.
  Import IR.

  (* EvalPatterns: total, deterministic match discovery *)
  Parameter eval_patterns : Graph.t -> IR.t -> list Match.t.
  Axiom eval_patterns_deterministic : forall G IR1 IR2,
    eval_patterns G IR1 = eval_patterns G IR2 -> IR1 = IR2.
  Axiom eval_patterns_total : forall G IR, exists M, eval_patterns G IR = M.

  (* Score computation *)
  Definition score (m : Match.t) (base_priority Z) (priority_scale Z) (fairness_scale Z) : Z :=
    (base_priority * priority_scale + m.(age) * fairness_scale)%Z.

  (* Compile: deterministic plan generation *)
  Parameter compile : Graph.t -> Match.t -> option (Action.alpha * list (string * Value.value)).
  Axiom compile_functional : forall G m a1 a2,
    compile G m = Some a1 -> compile G m = Some a2 -> a1 = a2.
  Axiom compile_nonfatal : forall G m, compile G m = None -> (* non-fatal error *) True.

  (* Simulate: apply α̂ on a copy *)
  Parameter simulate : Graph.t -> Action.alpha -> Graph.t.
  Axiom simulate_functional : forall G a G1 G2,
    simulate G a = G1 -> simulate G a = G2 -> G1 = G2.

  (* ValidateReads *)
  Parameter validate_reads : Counters.t -> list (string * Value.value) -> bool.
  Axiom validate_reads_functional : forall C R, validate_reads C R = true \/ validate_reads C R = false.

  (* Structural checks *)
  Parameter structural_checks : Graph.t -> Action.alpha -> bool.
  Axiom structural_checks_functional : forall G a, structural_checks G a = true \/ structural_checks G a = false.

  (* Re-evaluate constraints *)
  Parameter reevaluate_constraints : Graph.t -> Match.t -> bool.
  Axiom reevaluate_constraints_functional : forall G m, reevaluate_constraints G m = true \/ reevaluate_constraints G m = false.

  (* Resource checks *)
  Parameter resource_checks : Graph.t -> Counters.t -> option string. (* None = OK, Some error *)
  Axiom resource_checks_functional : forall G C, resource_checks G C = None \/ exists e, resource_checks G C = Some e.

  (* Apply α̂: produce new graph, counters, events *)
  Parameter apply_alpha : Graph.t -> Action.alpha -> Counters.t -> (Graph.t * Counters.t * list (string * list Value.value)).
  Axiom apply_alpha_functional : forall G a C res1 res2,
    apply_alpha G a C = res1 -> apply_alpha G a C = res2 -> res1 = res2.

End Helpers.

(* ---------------------------------------------------------------------- *)
(* 4. Formal SOS Rules (as Coq definitions/functions)                     *)
(* ---------------------------------------------------------------------- *)

Module SOS.

  Import Graph.
  Import Counters.
  Import Match.
  Import Action.
  Import Config.
  Import IR.
  Import Helpers.

  (* DISCOVER *)
  Definition discover (cfg : Config.t) (ir : IR.t) : Config.t * list Match.t :=
    let M := eval_patterns cfg.(G) ir in
    (cfg, M).

  (* SELECT (returns either a match or NO_MATCH indicator) *)
  Inductive select_result :=
  | Selected (m : Match.t)
  | NoMatch.
  Definition select (cfg : Config.t) (M : list Match.t) : select_result :=
    let M_rem := filter (fun m => not (Map.mem m.(key) cfg.(Rejected))) M in
    match M_rem with
    | [] => NoMatch
    | _ =>
      (* sort by score descending, then match_key ascending *)
      let sorted := sort (fun m1 m2 =>
        match Z.compare (score m1) (score m2) with
        | Lt => Lt
        | Eq => compare_match_key m1 m2
        | Gt => Gt
        end) M_rem in
      Selected (hd (default_match) sorted)
    end.
  (* Note: compare_match_key uses ORDER_CANONICAL *)

  (* PLAN *)
  Definition plan (G : Graph.t) (m : Match.t) : option (Action.alpha * list (string * Value.value)) :=
    compile G m.

  (* COMMIT *)
  Inductive commit_result :=
  | CommitSuccess (cfg' : Config.t) (events : list (string * list Value.value))
  | CommitReject
  | CommitFatal (error : string).

  Definition commit (cfg : Config.t) (m : Match.t) (alpha : Action.alpha) (R : list (string * Value.value)) : commit_result :=
    if not (validate_reads cfg.(C) R) then CommitReject
    else
      let G_temp := simulate cfg.(G) alpha in
      if not (structural_checks G_temp alpha) then CommitReject
      else if not (reevaluate_constraints G_temp m) then CommitReject
      else
        match resource_checks G_temp cfg.(C) with
        | Some err => CommitFatal err
        | None =>
          let (G_new, C_new, events) := apply_alpha cfg.(G) alpha cfg.(C) in
          let M_prev_new := Map.map (fun _ => cfg.(C).(tick_counter)) (cfg.(M_prev)) in
          let cfg' := {| G := G_new; C := C_new; M_prev := M_prev_new; Rejected := Map.empty |} in
          CommitSuccess cfg' events
        end.

  (* NO_MATCH *)
  Definition no_match (cfg : Config.t) : Config.t :=
    {| G := cfg.(G);
       C := {| tick_counter := cfg.(C).(tick_counter) + 1;
               seq_counter := cfg.(C).(seq_counter);
               type_extent_version := cfg.(C).(type_extent_version);
               element_version := cfg.(C).(element_version);
               adjacency_version := cfg.(C).(adjacency_version) |};
       M_prev := cfg.(M_prev);
       Rejected := Map.empty |}.

  (* Global transition δ *)
  Definition delta (cfg : Config.t) (ir : IR.t) : Config.t :=
    let (cfg_after_discover, M) := discover cfg ir in
    let rec loop (retries : nat) (current_cfg : Config.t) (rejected : Map.t Match.key unit) : Config.t :=
      match select {| current_cfg with Rejected := rejected |} M with
      | NoMatch => no_match current_cfg
      | Selected m =>
        match plan current_cfg.(G) m with
        | None =>
          (* non-fatal compile error -> retry *)
          if (retries >= Z.to_nat (List.length M))%nat then no_match current_cfg
          else loop (retries + 1) current_cfg (Map.add m.(key) tt rejected)
        | Some (alpha, R) =>
          match commit current_cfg m alpha R with
          | CommitReject =>
            if (retries >= Z.to_nat (List.length M))%nat then no_match current_cfg
            else loop (retries + 1) current_cfg (Map.add m.(key) tt rejected)
          | CommitFatal err => current_cfg (* error halt *)
          | CommitSuccess cfg' _ => cfg'
          end
        end
      end
    in
    loop 0 cfg_after_discover (Map.empty).

End SOS.

(* ---------------------------------------------------------------------- *)
(* 5. Determinism Theorems (Proof Obligations)                            *)
(* ---------------------------------------------------------------------- *)

Module DeterminismProofs.

  Import Graph.
  Import Counters.
  Import Match.
  Import Action.
  Import Config.
  Import IR.
  Import Helpers.
  Import SOS.

  (* Helper: eval_patterns is a function *)
  Lemma eval_patterns_functional : forall G ir M1 M2,
    eval_patterns G ir = M1 -> eval_patterns G ir = M2 -> M1 = M2.
  Proof.
    intros G ir M1 M2 H1 H2.
    rewrite H1 in H2. apply H2.
  Qed.

  (* Helper: select is deterministic given M and Rejected *)
  Lemma select_deterministic : forall cfg M res1 res2,
    select cfg M = res1 -> select cfg M = res2 -> res1 = res2.
  Proof.
    intros. unfold select in *.
    (* The filter and sort are deterministic if ORDER_CANONICAL is total and antisymmetric.
       The score and match_key comparison are deterministic. *)
    admit.
  Qed.

  (* Helper: compile is deterministic *)
  Lemma compile_deterministic : forall G m res1 res2,
    compile G m = res1 -> compile G m = res2 -> res1 = res2.
  Proof.
    intros. apply compile_functional; auto.
  Qed.

  (* Helper: commit is deterministic given same inputs *)
  Lemma commit_deterministic : forall cfg m alpha R res1 res2,
    commit cfg m alpha R = res1 ->
    commit cfg m alpha R = res2 ->
    res1 = res2.
  Proof.
    intros.
    (* unfold commit; all helpers are functional *)
    admit.
  Qed.

  (* Helper: no_match deterministic *)
  Lemma no_match_deterministic : forall cfg cfg1 cfg2,
    no_match cfg = cfg1 -> no_match cfg = cfg2 -> cfg1 = cfg2.
  Proof.
    intros. unfold no_match in *. congruence.
  Qed.

  (* Helper: recursive loop terminates by well-founded measure (|M|-|Rejected|) *)
  Lemma loop_termination : forall cfg ir,
    exists cfg', SOS.delta cfg ir = cfg'.
  Proof.
    admit.
  Qed.

  (* Main theorem: delta is a total function *)
  Theorem delta_functional : forall cfg ir cfg1 cfg2,
    SOS.delta cfg ir = cfg1 -> SOS.delta cfg ir = cfg2 -> cfg1 = cfg2.
  Proof.
    intros cfg ir cfg1 cfg2 H1 H2.
    (* The definition of delta is a deterministic program; all its components are deterministic.
       The loop is deterministic because each step is deterministic and the termination is well-founded.
       Thus, delta is a function. *)
    admit.
  Qed.

  (* Stronger: No two different execution traces for same input *)
  Theorem unique_execution : forall cfg ir,
    exists! cfg', SOS.delta cfg ir = cfg'.
  Proof.
    intros. apply deterministic_implies_unique. apply delta_functional.
    (* Need to prove existence separately *)
    admit.
  Qed.

End DeterminismProofs.

(* ---------------------------------------------------------------------- *)
(* 6. Additional Useful Lemmas (for future proof development)             *)
(* ---------------------------------------------------------------------- *)

Module AdditionalLemmas.

  Import OrderCanonical.

  (* ORDER_CANONICAL is a total order on all values *)
  Lemma order_canonical_total : forall v1 v2, compare_order_key v1 v2 = Eq \/ compare_order_key v1 v2 = Lt \/ compare_order_key v1 v2 = Gt.
  Proof. exact total_order. Qed.

  Lemma order_canonical_antisym : forall v1 v2, compare_order_key v1 v2 = Eq -> v1 = v2.
  Proof. exact antisym. Qed.

  Lemma order_canonical_trans : forall v1 v2 v3,
    compare_order_key v1 v2 = Lt -> compare_order_key v2 v3 = Lt -> compare_order_key v1 v3 = Lt.
  Proof. exact transitive. Qed.

  (* Lifted to match_key *)
  Lemma match_key_order_total : forall m1 m2, compare_match_key m1 m2 = Eq \/ compare_match_key m1 m2 = Lt \/ compare_match_key m1 m2 = Gt.
  Proof. admit. Qed.

End AdditionalLemmas.

(* ---------------------------------------------------------------------- *)
(* End of Coq Skeleton                                                    *)
(* ---------------------------------------------------------------------- *)
