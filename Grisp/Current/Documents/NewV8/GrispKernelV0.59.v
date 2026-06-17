(* GRISP Kernel – Coq Mechanization Skeleton (fixed, no IR alias) *)
Require Import List String ZArith Bool Program FunctionalExtensionality OrderedType Psatz Eqdep_dec.
Open Scope string_scope.
Import ListNotations.

(* ================================================================ *)
(* Generic map helpers                                              *)
(* ================================================================ *)

Definition map (K V : Type) := list (K * V).
Definition empty {K V} : map K V := [].
Definition add {K V} (k : K) (v : V) (m : map K V) : map K V := (k, v) :: m.
Definition mem {K V} (eq_dec : forall x y : K, {x = y} + {x <> y}) (k : K) (m : map K V) : bool :=
  List.existsb (fun p => if eq_dec (fst p) k then true else false) m.
Definition map_map {K V1 V2} (f : V1 -> V2) (m : map K V1) : map K V2 :=
  List.map (fun p => (fst p, f (snd p))) m.
Definition find {K V} (eq_dec : forall x y : K, {x = y} + {x <> y}) (k : K) (m : map K V) : option V :=
  match List.filter (fun p => if eq_dec (fst p) k then true else false) m with
  | [] => None
  | (_,v)::_ => Some v
  end.

(* ================================================================ *)
(* ID interface + implementation                                   *)
(* ================================================================ *)

Module Type ID.
  Parameter t : Type.
  Parameter type_name : t -> string.
  Parameter seq_num : t -> Z.
  Parameter eq_dec : forall x y : t, {x = y} + {x <> y}.
  Parameter compare : t -> t -> comparison.
  Axiom compare_spec :
    forall x y, CompareSpec (x = y) (compare x y = Lt) (compare x y = Gt) (compare x y).
  Axiom compare_type_name_seq :
    forall x y,
      compare x y =
      match String.compare (type_name x) (type_name y) with
      | Eq => Z.compare (seq_num x) (seq_num y)
      | c  => c
      end.
End ID.

Module IDImpl <: ID.
  Definition t := (string * Z)%type.
  Definition type_name (x : t) := fst x.
  Definition seq_num (x : t) := snd x.

  Definition eq_dec : forall x y : t, {x = y} + {x <> y}.
  Proof.
    intros [s1 z1] [s2 z2].
    destruct (String.string_dec s1 s2).
    - subst. destruct (Z.eq_dec z1 z2).
      + subst; left; reflexivity.
      + right; congruence.
    - right; congruence.
  Defined.

  Definition compare (x y : t) :=
    match String.compare (fst x) (fst y) with
    | Eq => Z.compare (snd x) (snd y)
    | c  => c
    end.

  Lemma compare_spec :
    forall x y,
      CompareSpec (x = y) (compare x y = Lt) (compare x y = Gt) (compare x y).
  Proof.
  Admitted.

  Lemma compare_type_name_seq :
    forall x y,
      compare x y =
      match String.compare (fst x) (fst y) with
      | Eq => Z.compare (snd x) (snd y)
      | c  => c
      end.
  Proof. reflexivity. Qed.
End IDImpl.

(* ================================================================ *)
(* Values                                                           *)
(* ================================================================ *)

Module Value.
  Inductive value :=
  | IntVal  (z : Z)
  | FixedVal (scale : nat) (scaled : Z)
  | BoolVal (b : bool)
  | StringVal (s : string)
  | IdentVal (id : IDImpl.t)
  | ListVal (l : list value)
  | MapVal  (m : list (value * value)).

  Lemma value_eq_dec : forall x y : value, {x = y} + {x <> y}.
  Proof.
  Admitted.
End Value.

Lemma String_compare_refl : forall s, String.compare s s = Eq.
Proof.
  intro s.
  destruct (String.compare s s) eqn:H.
  - reflexivity.
  - admit.
  - admit.
Admitted.

(* ================================================================ *)
(* Ordered field type                                               *)
(* ================================================================ *)

Module Field <: OrderedType.
  Definition t := string.
  Definition eq (x y : t) := x = y.

  Definition eq_dec (x y : t) : {eq x y} + {~ eq x y}.
  Proof. unfold eq; apply string_dec. Defined.

  Definition lt (x y : t) := String.compare x y = Lt.

  Lemma eq_refl : forall x : t, eq x x.
  Proof. intro x; reflexivity. Qed.

  Lemma eq_sym : forall x y : t, eq x y -> eq y x.
  Proof. intros x y H; unfold eq in H; subst; reflexivity. Qed.

  Lemma eq_trans : forall x y z : t, eq x y -> eq y z -> eq x z.
  Proof. intros x y z H1 H2; unfold eq in H1, H2; subst; reflexivity. Qed.

  Lemma lt_trans : forall x y z : t, lt x y -> lt y z -> lt x z.
  Proof.
    unfold lt; intros x y z Hxy Hyz.
  Admitted.

  Lemma lt_not_eq : forall x y : t, lt x y -> ~ eq x y.
  Proof.
    unfold lt, eq; intros x y Hlt Heq.
    subst.
    rewrite (String_compare_refl y) in Hlt.
    discriminate.
  Qed.

  Lemma compare : forall x y : t, Compare lt eq x y.
  Proof.
    intros x y.
    destruct (String.compare x y) eqn:H.
    - apply EQ.
      admit.
    - apply LT.
      exact H.
    - apply GT.
      admit.
  Admitted.
End Field.

Inductive dir := InDir | OutDir.

(* ================================================================ *)
(* GRAPH interface + implementation                                *)
(* ================================================================ *)

Module Type GRAPH.
  Record node := {
    node_id     : IDImpl.t;
    node_type   : string;
    node_fields : map Field.t Value.value
  }.

  Record edge := {
    edge_id     : IDImpl.t;
    edge_type   : string;
    edge_src    : IDImpl.t;
    edge_tgt    : IDImpl.t;
    edge_fields : map Field.t Value.value
  }.

  Record t := {
    nodes : map IDImpl.t node;
    edges : map IDImpl.t edge
  }.
End GRAPH.

Module Graph <: GRAPH.
  Include GRAPH.
End Graph.

(* ================================================================ *)
(* COUNTERS interface + implementation                             *)
(* ================================================================ *)

Module Type COUNTERS.
  Record t := {
    tick_counter       : Z;
    seq_counter        : map string Z;
    type_extent_version: map string Z;
    element_version    : map IDImpl.t Z;
    adjacency_version  : map (IDImpl.t * string * dir) Z
  }.
End COUNTERS.

Module Counters <: COUNTERS.
  Include COUNTERS.
End Counters.

(* ================================================================ *)
(* MATCH interface + implementation                                *)
(* ================================================================ *)

Module Type MATCH.
  Record t := {
    key       : (string * list (string * Value.value));
    bindings  : map string Value.value;
    read_set  : list (string * Value.value);
    age       : Z
  }.
End MATCH.

Module Match <: MATCH.
  Include MATCH.
End Match.

Definition match_key : Type :=
  (string * list (string * Value.value))%type.

Fixpoint list_pair_value_eq_dec
  (l1 l2 : list (string * Value.value))
  : {l1 = l2} + {l1 <> l2}.
Proof.
  destruct l1 as [| [s1 v1] l1'];
  destruct l2 as [| [s2 v2] l2'].
  - left; reflexivity.
  - right; discriminate.
  - right; discriminate.
  - destruct (string_dec s1 s2) as [Hs|Hs].
    + subst s2.
      destruct (Value.value_eq_dec v1 v2) as [Hv|Hv].
      * subst v2.
        destruct (list_pair_value_eq_dec l1' l2') as [Hl|Hl].
        -- subst l2'. left; reflexivity.
        -- right; intro H; inversion H; contradiction.
      * right; intro H; inversion H; contradiction.
    + right; intro H; inversion H; contradiction.
Defined.

Definition match_key_eq_dec
  (k1 k2 : match_key)
  : {k1 = k2} + {k1 <> k2}.
Proof.
  destruct k1 as [s1 l1].
  destruct k2 as [s2 l2].
  destruct (string_dec s1 s2) as [Hs|Hs].
  - subst s2.
    destruct (list_pair_value_eq_dec l1 l2) as [Hl|Hl].
    + subst l2. left; reflexivity.
    + right; intro H; inversion H; contradiction.
  - right; intro H; inversion H; contradiction.
Defined.

(* ================================================================ *)
(* ACTION interface + implementation                               *)
(* ================================================================ *)

Module Type ACTION.
  Inductive primitive :=
  | CreateNode (x : IDImpl.t) (typ : string) (fields : map Field.t Value.value)
  | CreateEdge (x : IDImpl.t) (typ : string) (src : IDImpl.t) (tgt : IDImpl.t) (fields : map Field.t Value.value)
  | UpdateField (target : IDImpl.t) (field : string) (new_val : Value.value)
  | DeleteEdge (e : IDImpl.t)
  | DeleteNode (x : IDImpl.t)
  | EmitEvent (event_type : string) (payload : list Value.value).
  Definition alpha := list primitive.
  Definition handle := nat.
  Definition alpha_with_handles := list (handle * primitive).
End ACTION.

Module Action <: ACTION.
  Include ACTION.
End Action.

(* ================================================================ *)
(* CONFIG interface + implementation                               *)
(* ================================================================ *)

Module Type CONFIG.
  Record t := {
    G        : Graph.t;
    C        : Counters.t;
    M_prev   : map match_key Z;
    Rejected : map match_key unit
  }.
End CONFIG.

Module Config <: CONFIG.
  Include CONFIG.
End Config.

(* ================================================================ *)
(* IR interface + implementation                                   *)
(* ================================================================ *)

Module Type IR.
  Record rule := {
    rule_id        : string;
    base_priority  : Z;
    priority_scale : Z;
    fairness_scale : Z;
    pattern        : list (string * string);
    constraints    : list (string * Value.value);
    let_bindings   : list (string * Value.value);
    actions        : list Action.primitive
  }.
  Definition t := list rule.
End IR.

Module IRImpl <: IR.
  Include IR.
End IRImpl.

(* ================================================================ *)
(* Canonical ordering on values                                    *)
(* ================================================================ *)

Module OrderCanonical.
  Import Value IDImpl.

  Parameter compare_order_key_list :
    forall A : Type, list A -> list A -> comparison.

  Fixpoint order_key (v : value) : list nat :=
    match v with
    | IntVal z              => [0; Z.to_nat z]
    | FixedVal scale scaled => [1; scale; Z.to_nat scaled]
    | BoolVal b             => [2; if b then 1 else 0]
    | StringVal s           => [3; String.length s]
    | IdentVal id           => [4; Z.to_nat (IDImpl.seq_num id)]
    | ListVal l             => 5 :: List.concat (List.map order_key l)
    | MapVal m              => [6]
    end.

  Definition compare_order_key (v1 v2 : value) :=
    compare_order_key_list _ (order_key v1) (order_key v2).

  Axiom order_key_inj :
    forall v1 v2, order_key v1 = order_key v2 -> v1 = v2.

  Axiom order_key_compare :
    forall v1 v2,
      compare_order_key v1 v2 =
      compare_order_key_list _ (order_key v1) (order_key v2).

  Theorem total_order :
    forall v1 v2,
      compare_order_key v1 v2 = Eq \/
      compare_order_key v1 v2 = Lt \/
      compare_order_key v1 v2 = Gt.
  Proof. Admitted.

  Theorem antisym :
    forall v1 v2, compare_order_key v1 v2 = Eq -> v1 = v2.
  Proof. Admitted.

  Theorem transitive :
    forall v1 v2 v3,
      compare_order_key v1 v2 = Lt ->
      compare_order_key v2 v3 = Lt ->
      compare_order_key v1 v3 = Lt.
  Proof. Admitted.
End OrderCanonical.

Definition compare_binding '(s1, v1) '(s2, v2) :=
  match String.compare s1 s2 with
  | Eq => OrderCanonical.compare_order_key v1 v2
  | c  => c
  end.

Fixpoint compare_binding_list l1 l2 :=
  match l1, l2 with
  | [], [] => Eq
  | [], _  => Lt
  | _, []  => Gt
  | b1 :: t1, b2 :: t2 =>
      match compare_binding b1 b2 with
      | Eq => compare_binding_list t1 t2
      | c  => c
      end
  end.

Definition compare_match_key (m1 m2 : Match.t) : comparison :=
  match String.compare (fst m1.(Match.key)) (fst m2.(Match.key)) with
  | Eq => compare_binding_list (snd m1.(Match.key)) (snd m2.(Match.key))
  | c  => c
  end.

Definition default_match : Match.t :=
  {| Match.key := ("", []);
     Match.bindings := [];
     Match.read_set := [];
     Match.age := 0 |}.



(* ================================================================ *)
(* Helpers                                                          *)
(* ================================================================ *)

Module Helpers.
  Import Graph Counters Match Action Config IRImpl.

  Parameter eval_patterns : Graph.t -> IRImpl.t -> list Match.t.
  Axiom eval_patterns_deterministic :
    forall G IR1 IR2,
      eval_patterns G IR1 = eval_patterns G IR2 -> IR1 = IR2.
  Axiom eval_patterns_total :
    forall G IR, exists M, eval_patterns G IR = M.

  Definition score (m : Match.t)
             (base_priority priority_scale fairness_scale : Z) :=
    (base_priority * priority_scale + m.(Match.age) * fairness_scale)%Z.

  Parameter compile :
    Graph.t -> Match.t -> option (Action.alpha * list (string * Value.value)).
  Axiom compile_functional :
    forall G m a1 a2,
      compile G m = Some a1 ->
      compile G m = Some a2 ->
      a1 = a2.
  Axiom compile_nonfatal :
    forall G m, compile G m = None -> True.

  Parameter simulate : Graph.t -> Action.alpha -> Graph.t.
  Axiom simulate_functional :
    forall G a G1 G2,
      simulate G a = G1 ->
      simulate G a = G2 ->
      G1 = G2.

  Parameter validate_reads :
    Counters.t -> list (string * Value.value) -> bool.
  Axiom validate_reads_functional :
    forall C R, validate_reads C R = true \/ validate_reads C R = false.

  Parameter structural_checks :
    Graph.t -> Action.alpha -> bool.
  Axiom structural_checks_functional :
    forall G a, structural_checks G a = true \/ structural_checks G a = false.

  Parameter reevaluate_constraints :
    Graph.t -> Match.t -> bool.
  Axiom reevaluate_constraints_functional :
    forall G m, reevaluate_constraints G m = true \/ reevaluate_constraints G m = false.

  Parameter resource_checks :
    Graph.t -> Counters.t -> option string.
  Axiom resource_checks_functional :
    forall G C, resource_checks G C = None \/ exists e, resource_checks G C = Some e.

  Parameter apply_alpha :
    Graph.t -> Action.alpha -> Counters.t ->
    (Graph.t * Counters.t * list (string * list Value.value)).
  Axiom apply_alpha_functional :
    forall G a C res1 res2,
      apply_alpha G a C = res1 ->
      apply_alpha G a C = res2 ->
      res1 = res2.
End Helpers.

(* ================================================================ *)
(* SOS                                                              *)
(* ================================================================ *)

Module SOS.
  Import Graph Counters Match Action Config IRImpl Helpers.

  Definition discover (cfg : Config.t) (ir : IRImpl.t) :=
    (cfg, eval_patterns cfg.(Config.G) ir).

  Inductive select_result :=
  | Selected (m : Match.t)
  | NoMatch.

  Definition select (cfg : Config.t) (M : list Match.t) : select_result :=
    let M_rem :=
      filter (fun m =>
        negb (mem match_key_eq_dec m.(Match.key) cfg.(Config.Rejected))) M in
    match M_rem with
    | [] => NoMatch
    | _  =>
      let sorted :=
        sort (fun m1 m2 =>
          match Z.compare (score m1 0 1 1) (score m2 0 1 1) with
          | Lt => Lt
          | Eq => compare_match_key m1 m2
          | Gt => Gt
          end) M_rem in
      Selected (hd default_match sorted)
    end.

  Definition plan := compile.

  Inductive commit_result :=
  | CommitSuccess (cfg' : Config.t) (events : list (string * list Value.value))
  | CommitReject
  | CommitFatal (error : string).

  Definition commit (cfg : Config.t)
                    (m : Match.t)
                    (alpha : Action.alpha)
                    (R : list (string * Value.value)) : commit_result :=
    if negb (validate_reads cfg.(Config.C) R) then CommitReject else
    let G_temp := simulate cfg.(Config.G) alpha in
    if negb (structural_checks G_temp alpha) then CommitReject else
    if negb (reevaluate_constraints G_temp m) then CommitReject else
    match resource_checks G_temp cfg.(Config.C) with
    | Some err => CommitFatal err
    | None =>
      let '(G_new, C_new, events) := apply_alpha cfg.(Config.G) alpha cfg.(Config.C) in
      let M_prev_new :=
        map_map (fun _ => cfg.(Config.C).(Counters.tick_counter)) (cfg.(Config.M_prev)) in
      let cfg' :=
        {| Config.G        := G_new;
           Config.C        := C_new;
           Config.M_prev   := M_prev_new;
           Config.Rejected := empty |} in
      CommitSuccess cfg' events
    end.

  Definition no_match (cfg : Config.t) : Config.t :=
    {| Config.G := cfg.(Config.G);
       Config.C := {| Counters.tick_counter       := cfg.(Config.C).(Counters.tick_counter) + 1;
                      Counters.seq_counter        := cfg.(Config.C).(Counters.seq_counter);
                      Counters.type_extent_version:= cfg.(Config.C).(Counters.type_extent_version);
                      Counters.element_version    := cfg.(Config.C).(Counters.element_version);
                      Counters.adjacency_version  := cfg.(Config.C).(Counters.adjacency_version) |};
       Config.M_prev   := cfg.(Config.M_prev);
       Config.Rejected := empty |}.

  Definition delta (cfg : Config.t) (ir : IRImpl.t) : Config.t :=
    let '(cfg_after_discover, M) := discover cfg ir in
    let fix loop (retries : nat)
                 (current_cfg : Config.t)
                 (rejected : map match_key unit) : Config.t :=
      match select {| current_cfg with Config.Rejected := rejected |} M with
      | NoMatch => no_match current_cfg
      | Selected m =>
        match plan current_cfg.(Config.G) m with
        | None =>
          if (retries >= Z.to_nat (List.length M))%nat
          then no_match current_cfg
          else loop (S retries) current_cfg (add m.(Match.key) tt rejected)
        | Some (alpha, R) =>
          match commit current_cfg m alpha R with
          | CommitReject =>
            if (retries >= Z.to_nat (List.length M))%nat
            then no_match current_cfg
            else loop (S retries) current_cfg (add m.(Match.key) tt rejected)
          | CommitFatal _err => current_cfg
          | CommitSuccess cfg' _events => cfg'
          end
        end
      end
    in loop 0 cfg_after_discover empty.
End SOS.

(* ================================================================ *)
(* Determinism proofs                                               *)
(* ================================================================ *)

Module DeterminismProofs.
  Import Graph Counters Match Action Config IRImpl Helpers SOS.

  Lemma eval_patterns_functional :
    forall G ir M1 M2,
      eval_patterns G ir = M1 ->
      eval_patterns G ir = M2 ->
      M1 = M2.
  Proof.
    intros G ir M1 M2 H1 H2.
    rewrite H1 in H2; assumption.
  Qed.

  Lemma select_deterministic :
    forall cfg M res1 res2,
      select cfg M = res1 ->
      select cfg M = res2 ->
      res1 = res2.
  Proof. Admitted.

  Lemma compile_deterministic :
    forall G m res1 res2,
      compile G m = res1 ->
      compile G m = res2 ->
      res1 = res2.
  Proof.
    intros G m res1 res2 H1 H2.
    destruct res1, res2; try congruence.
    eapply compile_functional; eauto.
  Qed.

  Lemma commit_deterministic :
    forall cfg m alpha R res1 res2,
      commit cfg m alpha R = res1 ->
      commit cfg m alpha R = res2 ->
      res1 = res2.
  Proof. Admitted.

  Lemma no_match_deterministic :
    forall cfg cfg1 cfg2,
      no_match cfg = cfg1 ->
      no_match cfg = cfg2 ->
      cfg1 = cfg2.
  Proof.
    intros cfg cfg1 cfg2 H1 H2.
    unfold no_match in *; congruence.
  Qed.

  Lemma loop_termination :
    forall cfg ir, exists cfg', SOS.delta cfg ir = cfg'.
  Proof. Admitted.

  Theorem delta_functional :
    forall cfg ir cfg1 cfg2,
      SOS.delta cfg ir = cfg1 ->
      SOS.delta cfg ir = cfg2 ->
      cfg1 = cfg2.
  Proof. Admitted.

  Theorem unique_execution :
    forall cfg ir, exists! cfg', SOS.delta cfg ir = cfg'.
  Proof.
    intros cfg ir.
    apply deterministic_implies_unique.
    - apply delta_functional.
    - admit.
  Qed.
End DeterminismProofs.

(* ================================================================ *)
(* Additional lemmas                                                *)
(* ================================================================ *)

Module AdditionalLemmas.
  Import OrderCanonical.

  Lemma order_canonical_total :
    forall v1 v2,
      compare_order_key v1 v2 = Eq \/
      compare_order_key v1 v2 = Lt \/
      compare_order_key v1 v2 = Gt.
  Proof. exact total_order. Qed.

  Lemma order_canonical_antisym :
    forall v1 v2, compare_order_key v1 v2 = Eq -> v1 = v2.
  Proof. exact antisym. Qed.

  Lemma order_canonical_trans :
    forall v1 v2 v3,
      compare_order_key v1 v2 = Lt ->
      compare_order_key v2 v3 = Lt ->
      compare_order_key v1 v3 = Lt.
  Proof. exact transitive. Qed.

  Lemma match_key_order_total :
    forall m1 m2,
      compare_match_key m1 m2 = Eq \/
      compare_match_key m1 m2 = Lt \/
      compare_match_key m1 m2 = Gt.
  Proof. Admitted.
End AdditionalLemmas.
