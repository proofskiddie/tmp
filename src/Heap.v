Require Import
  ByteString.Tactics
  ByteString.Nomega
  ByteString.Memory
  ByteString.FMapExt
  ByteString.Fiat
  ByteString.FromADT
  Coq.FSets.FMapFacts
  Coq.Structures.DecidableTypeEx.

Generalizable All Variables.

Module Heap (M : WSfun N_as_DT).

Module Import FMapExt := FMapExt N_as_DT M.
Module P := FMapExt.P.
Module F := P.F.

Open Scope string_scope.

Definition emptyS   := "empty".
Definition allocS   := "alloc".
Definition reallocS := "realloc".
Definition freeS    := "free".
Definition peekS    := "peek".
Definition pokeS    := "poke".
Definition memcpyS  := "memcpy".
Definition memsetS  := "memset".

Record HeapState := {
  resvs : M.t Size;
  bytes : M.t Word
}.

Definition HeapState_Equal (x y : HeapState) : Prop :=
  M.Equal (resvs x) (resvs y) /\ M.Equal (bytes x) (bytes y).

Global Program Instance Build_HeapState_Proper :
  Proper (M.Equal ==> M.Equal ==> HeapState_Equal) Build_HeapState.
Obligation 1. relational; unfold HeapState_Equal; simpl; intuition. Qed.

Ltac tsubst :=
  repeat
    match goal with
    | [ H : (_, _) = (_, _) |- _ ] => inv H
    | [ H : (_, _, _) = (_, _, _) |- _ ] => inv H
    | [ H : (_, _, _, _) = (_, _, _, _) |- _ ] => inv H
    | [ H : {| resvs := _
             ; bytes := _ |} =
            {| resvs := _
             ; bytes := _ |} |- _ ] => inv H
    end;
  subst.

Definition newHeapState :=
  {| resvs := M.empty _
   ; bytes := M.empty _ |}.

Definition find_free_block (len : Size) (r : M.t Ptr) : Comp Ptr :=
  { addr : N | P.for_all (fun a sz => negb (overlaps_bool a sz addr len)) r }.

Definition keep_keys (P : M.key -> bool) : M.t Word -> M.t Word :=
  P.filter (const ∘ P).

Definition keep_range (addr : Ptr) (len : Size) : M.t Word -> M.t Word :=
  keep_keys (within_bool addr len).

Definition drop_range (addr : Ptr) (len : Size) : M.t Word -> M.t Word :=
  keep_keys (fun p => negb (within_bool addr len p)).

Definition copy_bytes (from to len : Ptr) (bytes : M.t Word) : M.t Word :=
  P.update (drop_range to len bytes)
           (M.fold (fun k e rest =>
                      If within_bool from len k
                      Then M.add (k - from + to) e rest
                      Else rest)
                   bytes (M.empty _)).

Program Instance copy_bytes_Proper :
  Proper (eq ==> eq ==> eq ==> M.Equal ==> M.Equal) copy_bytes.
Obligation 1.
  relational.
  unfold copy_bytes, drop_range, keep_range, keep_keys.
  apply P.update_m; trivial.
    rewrite H2; reflexivity.
  apply P.fold_Equal; eauto; relational.
  - destruct (within_bool y y1 y3); simpl;
    rewrite H1; reflexivity.
  - intros ??????.
    destruct (within_bool y y1 k) eqn:Heqe; simpl;
    destruct (within_bool y y1 k') eqn:Heqe1; simpl;
    try reflexivity.
    rewrite add_associative.
      reflexivity.
    intros.
    apply N.add_cancel_r in H0.
    apply Nsub_eq in H0; try tauto; nomega.
Qed.

Lemma copy_bytes_mapsto : forall k e addr1 addr2 len m,
  M.MapsTo k e (copy_bytes addr1 addr2 len m)
    <-> (If within_bool addr2 len k
         Then M.MapsTo ((k - addr2) + addr1) e m
         Else M.MapsTo k e m).
Proof.
  unfold copy_bytes, drop_range, keep_range, keep_keys,
         const, not, compose.
  split; intros.
    apply P.update_mapsto_iff in H.
    destruct H.
      revert H.
      apply P.fold_rec_bis; simpl; intros; intuition.
        destruct (within_bool addr2 len k) eqn:Heqe; simpl in *;
        rewrite <- H; assumption.
      destruct (within_bool addr2 len k) eqn:Heqe; simpl in *.
        destruct (within_bool addr1 len k0) eqn:Heqe1; simpl in *.
          simplify_maps.
            simplify_maps.
            nomega.
          simplify_maps; right; split; [nomega|intuition].
        simplify_maps; right; split; [nomega|intuition].
      destruct (within_bool addr1 len k0) eqn:Heqe1; simpl in *.
        simplify_maps.
          simplify_maps.
          nomega.
        simplify_maps.
        right.
        split.
          specialize (H1 H6).
          unfold not; intros; subst.
          contradiction H0.
          apply in_mapsto_iff.
          exists e.
          assumption.
        intuition.
      simplify_maps.
      right.
      split.
        specialize (H1 H2).
        unfold not; intros; subst.
        contradiction H0.
        apply in_mapsto_iff.
        exists e.
        assumption.
      intuition.
    destruct H.
    destruct (within_bool addr2 len k) eqn:Heqe; simpl in *.
      simplify_maps; relational.
      nomega.
    simplify_maps; relational.
  apply P.update_mapsto_iff.
  destruct (within_bool addr2 len k) eqn:Heqe; simpl in *.
    left.
    revert H.
    apply P.fold_rec_bis; simpl; intros; intuition.
      rewrite <- H in H1.
      intuition.
    destruct (within_bool addr1 len k0) eqn:Heqel; simpl.
      simplify_maps.
        simplify_maps.
        nomega.
      simplify_maps.
      right.
      split.
        nomega.
      intuition.
    simplify_maps.
    nomega.
  right.
  split.
    simplify_maps; relational.
    split; trivial.
    nomega.
  apply P.fold_rec_bis; simpl; intros; intuition.
    inversion H0.
    simplify_maps.
  destruct (within_bool addr1 len k0) eqn:Heqel; simpl in *.
    apply (proj1 (in_mapsto_iff _ _ _)) in H3.
    destruct H3.
    simplify_maps.
      nomega.
    contradiction H2.
    apply in_mapsto_iff.
    exists x.
    assumption.
  contradiction.
Qed.

Lemma copy_bytes_zero addr1 addr2 m : M.Equal (copy_bytes addr1 addr2 0 m) m.
Proof.
  apply F.Equal_mapsto_iff; split; intros;
  [ apply copy_bytes_mapsto in H
  | apply copy_bytes_mapsto ];
  destruct (within_bool addr2 0 k) eqn:Heqe; simpl in *; trivial;
  nomega.
Qed.

Lemma copy_bytes_idem d len m : M.Equal (copy_bytes d d len m) m.
Proof.
  apply F.Equal_mapsto_iff; split; intros;
  [ apply copy_bytes_mapsto in H
  | apply copy_bytes_mapsto ];
  destruct (within_bool d len k) eqn:Heqe; simpl in *; trivial;
  revert H; replace (k - d + d) with k by nomega; trivial.
Qed.

Definition HeapSpec := Def ADT {
  (* Map of memory addresses to blocks, which contain another mapping from
     offsets to initialized bytes. *)
  rep := HeapState,

  Def Constructor0 emptyS : rep := ret newHeapState,,

  (* Allocation returns the address for the newly allocated block.
     NOTE: conditions such as out-of-memory are not handled here; the final
     implementation must decide how to handle this operationally, such as by
     throwing an exception. It remains a further research question how to
     specify error handling at this level, when certain errors -- such as
     exhausting memory -- do not belong here, since a mathematical machine has
     no such limits. *)
  Def Method1 allocS (r : rep) (len : Size | 0 < len) : rep * Ptr :=
    addr <- find_free_block (` len) (resvs r);
    ret ({| resvs := M.add addr (` len) (resvs r)
          ; bytes := bytes r |}, addr),

  (* Freeing an unallocated block is a no-op. *)
  Def Method1 freeS (r : rep) (addr : Ptr) : rep * unit :=
    ret ({| resvs := M.remove addr (resvs r)
          ; bytes := bytes r |}, tt),

  (* Realloc is not required to reuse the same block. If the address does not
     identify an allociated region, a new memory block is returned without any
     bytes moved. If a block did exist previously, as many bytes as possible
     are copied to the new block. *)
  Def Method2 reallocS (r : rep) (addr : Ptr) (len : Size | 0 < len) :
    rep * Ptr :=
    naddr <- find_free_block (` len) (M.remove addr (resvs r));
    ret ({| resvs := M.add naddr (` len) (M.remove addr (resvs r))
          ; bytes :=
              Ifopt M.find addr (resvs r) as sz
              Then copy_bytes addr naddr (N.min sz (` len)) (bytes r)
              Else bytes r |}, naddr),

  (* Peeking an uninitialized address allows any value to be returned. *)
  Def Method1 peekS (r : rep) (addr : Ptr) : rep * Word :=
    p <- { p : Word | forall v, M.MapsTo addr v (bytes r) -> p = v };
    ret (r, p),

  Def Method2 pokeS (r : rep) (addr : Ptr) (w : Word) : rep * unit :=
    ret ({| resvs := resvs r
          ; bytes := M.add addr w (bytes r) |}, tt),

  (* Data may only be copied from one allocated block to another (or within
     the same block), and the region must fit within both source and
     destination. Otherwise, the operation is a no-op. *)
  Def Method3 memcpyS (r : rep) (addr1 : Ptr) (addr2 : Ptr) (len : Size) :
    rep * unit :=
    ret ({| resvs := resvs r
          ; bytes := copy_bytes addr1 addr2 len (bytes r) |}, tt),

  (* Any attempt to memset bytes outside of an allocated block is a no-op. *)
  Def Method3 memsetS (r : rep) (addr : Ptr) (len : Size) (w : Word) :
    rep * unit :=
    ret ({| resvs := resvs r
          ; bytes :=
              P.update (bytes r)
                       (N.peano_rect (fun _ => M.t Word) (bytes r)
                                     (fun i => M.add (addr + i)%N w)
                                     len) |}, tt)

}%ADTParsing.

Definition empty : Comp (Rep HeapSpec) :=
  Eval simpl in callCons HeapSpec emptyS.

Definition alloc (r : Rep HeapSpec) (len : Size | 0 < len) :
  Comp (Rep HeapSpec * N) :=
  Eval simpl in callMeth HeapSpec allocS r len.

Definition free (r : Rep HeapSpec) (addr : Ptr) :
  Comp (Rep HeapSpec * unit) :=
  Eval simpl in callMeth HeapSpec freeS r addr.

Definition realloc (r : Rep HeapSpec) (addr : Ptr) (len : Size | 0 < len) :
  Comp (Rep HeapSpec * N) :=
  Eval simpl in callMeth HeapSpec reallocS r addr len.

Definition peek (r : Rep HeapSpec) (addr : Ptr) :
  Comp (Rep HeapSpec * Word) :=
  Eval simpl in callMeth HeapSpec peekS r addr.

Definition poke (r : Rep HeapSpec) (addr : Ptr) (w : Word) :
  Comp (Rep HeapSpec * unit) :=
  Eval simpl in callMeth HeapSpec pokeS r addr w.

Definition memcpy (r : Rep HeapSpec) (addr : Ptr) (addr2 : Ptr) (len : Size) :
  Comp (Rep HeapSpec * unit) :=
  Eval simpl in callMeth HeapSpec memcpyS r addr addr2 len.

Definition memset (r : Rep HeapSpec) (addr : Ptr) (len : Ptr) (w : Word) :
  Comp (Rep HeapSpec * unit) :=
  Eval simpl in callMeth HeapSpec memsetS r addr len w.

(**
 ** Theorems related to the Heap specification.
 **)

Ltac inspect :=
  destruct_computations; simpl in *;
  repeat breakdown;
  repeat (simplify_maps; simpl in *;
          destruct_computations; simpl in *;
          repeat breakdown).

Ltac complete IHfromADT :=
  inspect;
  try match goal with
    [ H : (?X =? ?Y) = true |- _ ] => apply N.eqb_eq in H; subst
  end;
  try (eapply IHfromADT; eassumption);
  try solve [ eapply IHfromADT; try eassumption; inspect
            | try eapply IHfromADT; eassumption
            | inspect;
              try (unfold fits, within in *; inspect; nomega);
              eapply IHfromADT; try eassumption; inspect
            | discriminate ].

Theorem allocations_have_size : forall r : Rep HeapSpec, fromADT _ r ->
  forall addr sz, M.MapsTo addr sz (resvs r) -> 0 < sz.
Proof.
  intros.
  generalize dependent sz.
  generalize dependent addr.
  ADT induction r; complete IHfromADT.
Qed.

Theorem allocations_no_overlap : forall r : Rep HeapSpec, fromADT _ r ->
  forall addr1 sz1, M.MapsTo addr1 sz1 (resvs r) ->
  forall addr2 sz2, M.MapsTo addr2 sz2 (resvs r)
    -> addr1 <> addr2
    -> ~ overlaps addr1 sz1 addr2 sz2.
Proof.
  intros.
  pose proof (allocations_have_size H H0).
  pose proof (allocations_have_size H H1).
  generalize dependent sz2.
  generalize dependent addr2.
  generalize dependent sz1.
  generalize dependent addr1.
  ADT induction r; complete IHfromADT.
  - apply_for_all; nomega.
  - apply_for_all; nomega.
  - eapply M.remove_2 in H4; eauto.
    apply_for_all; nomega.
  - clear H8.
    eapply M.remove_2 in H4; eauto.
    apply not_overlaps_sym.
    apply_for_all; nomega.
Qed.

Theorem allocations_no_overlap_r : forall r : Rep HeapSpec, fromADT _ r ->
  forall addr1 sz1,
    P.for_all (fun a sz => negb (overlaps_bool a sz addr1 sz1)) (resvs r)
      -> 0 < sz1
      -> ~ M.In addr1 (resvs r).
Proof.
  unfold not; intros.
  generalize dependent sz1.
  generalize dependent addr1.
  ADT induction r; complete IHfromADT.
  - inversion H2.
    simplify_maps.
  - apply (proj1 (in_mapsto_iff _ _ _)) in H2.
    destruct H2.
    apply for_all_add_true in H1;
    relational; simpl in *.
      simplify_maps.
        nomega.
      assert (M.In addr1 (resvs r)).
        apply in_mapsto_iff.
        exists x1; assumption.
      eapply IHfromADT; eauto.
      nomega.
    unfold not; intros.
    eapply IHfromADT; eauto.
  - apply (proj1 (in_mapsto_iff _ _ _)) in H2.
    destruct H2.
    simplify_maps.
    eapply for_all_remove_inv in H1; relational.
      eapply IHfromADT; eauto.
      apply in_mapsto_iff.
      exists x0; assumption.
    unfold not; intros.
    apply (proj1 (in_mapsto_iff _ _ _)) in H0.
    destruct H0.
    pose proof (allocations_have_size H H4).
    apply not_eq_sym in H2.
    eapply F.remove_neq_mapsto_iff in H4; eauto.
    apply_for_all; relational.
    nomega.
  - apply (proj1 (in_mapsto_iff _ _ _)) in H2.
    destruct H2.
    simpl in *.
    apply_for_all; relational.
    rewrite <- remove_add in H1.
    simplify_maps.
      apply for_all_add_true in H1; relational; simpl in *.
        nomega.
      simplify_maps.
    rewrite remove_add in H1.
    apply_for_all; relational.
    simplify_maps.
    pose proof (allocations_have_size H H6).
    nomega.
Qed.

Corollary allocations_unique_fits : forall r : Rep HeapSpec, fromADT _ r ->
  forall base sz addr len,
    M.MapsTo base sz (resvs r) ->
    fits base sz addr len ->
    unique (fun a' b' => fits_bool a' b' addr len) base (resvs r).
Proof.
  unfold unique; intros.
  apply P.for_all_iff; relational; intros.
  simplify_maps.
  pose proof (allocations_no_overlap H H0 H4 H3); nomega.
Qed.

Corollary allocations_unique_within : forall r : Rep HeapSpec, fromADT _ r ->
  forall base sz addr,
    M.MapsTo base sz (resvs r) ->
    within base sz addr ->
    unique (fun a' b' => within_bool a' b' addr) base (resvs r).
Proof.
  unfold unique; intros.
  apply P.for_all_iff; relational; intros.
  simplify_maps.
  pose proof (allocations_no_overlap H H0 H4 H3); nomega.
Qed.

Corollary find_partitions_a_singleton : forall r : Rep HeapSpec, fromADT _ r ->
  forall addr base sz,
    M.MapsTo base sz (resvs r)
      -> within base sz addr
      -> M.Equal (P.filter (fun a b => within_bool a b addr) (resvs r))
                 (singleton base sz).
Proof.
  intros.
  pose proof (allocations_no_overlap H H0).
  apply F.Equal_mapsto_iff; intros.
  split; intros.
    unfold singleton.
    simplify_maps; relational.
    simplify_maps.
    destruct (N.eq_dec base k); subst.
      pose proof (F.MapsTo_fun H4 H0); subst.
      left; intuition.
    right; intuition.
    specialize (H2 _ _ H4 n).
    contradiction H2.
    nomega.
  unfold singleton in H3.
  simplify_maps.
  simplify_maps; relational.
  intuition; nomega.
Qed.

Corollary allocations_disjoint : forall r : Rep HeapSpec, fromADT _ r ->
  forall addr sz, M.MapsTo addr sz (resvs r)
    -> forall pos, within addr sz pos
    -> forall addr' sz', M.MapsTo addr' sz' (resvs r)
         -> addr <> addr'
         -> ~ within addr' sz' pos.
Proof. intros; pose proof (allocations_no_overlap H H0 H2 H3); nomega. Qed.

End Heap.

Module HeapADT (M : WSfun N_as_DT).

Module Import Heap := Heap M.

Open Scope N_scope.

Lemma empty_fromADT r :
  callCons HeapSpec emptyS ↝ r -> fromADT HeapSpec r.
Proof. check constructor (fromCons HeapSpec emptyS r). Qed.

Lemma alloc_fromADT r :
  fromADT HeapSpec r
    -> forall (len : Size | 0 < len) v,
         callMeth HeapSpec allocS r len ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec allocS r (fst v)). Qed.

Lemma free_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) v,
         callMeth HeapSpec freeS r addr ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec freeS r (fst v)). Qed.

Lemma realloc_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) (len : Size | 0 < len) v,
         callMeth HeapSpec reallocS r addr len ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec reallocS r (fst v)). Qed.

Lemma peek_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) v,
         callMeth HeapSpec peekS r addr ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec peekS r (fst v)). Qed.

Lemma poke_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) w v,
         callMeth HeapSpec pokeS r addr w ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec pokeS r (fst v)). Qed.

Lemma memcpy_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) (addr2 : Ptr) (len : Size) v,
         callMeth HeapSpec memcpyS r addr addr2 len ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec memcpyS r (fst v)). Qed.

Lemma memset_fromADT r :
  fromADT HeapSpec r
    -> forall (addr : Ptr) (len : Size) (w : Word) v,
         callMeth HeapSpec memsetS r addr len w ↝ v
    -> fromADT HeapSpec (fst v).
Proof. intros; check method (fromMeth HeapSpec memsetS r (fst v)). Qed.

Theorem HeapSpecADT : { adt : _ & refineADT HeapSpec adt }.
Proof.
  eexists.
  hone representation using
    (fun (or : Rep HeapSpec)
         (nr : { r : Rep HeapSpec | fromADT HeapSpec r }) => or = ` nr).
  resolve_constructor empty empty_fromADT.
  resolve_method r_n (alloc (` r_n) d)
                     (@alloc_fromADT _ (proj2_sig r_n) d).
  resolve_method r_n (free (` r_n) d)
                     (@free_fromADT _ (proj2_sig r_n) d).
  resolve_method r_n (realloc (` r_n) d d0)
                     (@realloc_fromADT _ (proj2_sig r_n) d d0).
  resolve_method r_n (peek (` r_n) d)
                     (@peek_fromADT _ (proj2_sig r_n) d).
  resolve_method r_n (poke (` r_n) d d0)
                     (@poke_fromADT _ (proj2_sig r_n) d d0).
  resolve_method r_n (memcpy (` r_n) d d0 d1)
                     (@memcpy_fromADT _ (proj2_sig r_n) d d0 d1).
  resolve_method r_n (memset (` r_n) d d0 d1)
                     (@memset_fromADT _ (proj2_sig r_n) d d0 d1).
  apply reflexivityT.
Defined.

End HeapADT.

Module HeapCanonical (M : WSfun N_as_DT).

Module Import HeapADT := HeapADT M.
Import Heap.
Import Heap.FMapExt.
Module P := FMapExt.P.
Module F := P.F.

Open Scope N_scope.

(** In order to refine to a computable heap, we have to add the notion of
    "free memory", from which addresses may be allocated. A further
    optimization here would be to add a free list, to which free blocks are
    returned, in order avoid gaps in the heap. A yet further optimization
    would be to better manage the free space to avoid fragmentation. The
    implementation below simply grows the heap with every allocation. *)

Lemma HeapCanonical : FullySharpened HeapSpec.
Proof.
  start sharpening ADT.
  eapply SharpenStep; [ apply (projT2 HeapSpecADT) |].

  hone representation using
       (fun or nr =>
          M.Equal (resvs (` or)) (resvs (snd nr)) /\
          M.Equal (bytes (` or)) (bytes (snd nr)) /\
          P.for_all (fun addr sz => addr + sz <=? fst nr)
                    (resvs (snd nr))).

  refine method emptyS.
  {
    remove_dependency (empty_fromADT (ReturnComputes _)).
    refine pick val (0%N, newHeapState).
      finish honing.
    intuition; simpl.
    apply for_all_empty; relational.
  }

  refine method allocS.
  {
    unfold find_free_block.
    remove_dependency alloc_fromADT.

    refine pick val (fst r_n).
    {
      simplify with monad laws; simpl.

      refine pick val (fst r_n + ` d,
                       {| resvs := M.add (fst r_n) (` d) (resvs (snd r_n))
                        ; bytes := bytes (snd r_n) |}).
        simplify with monad laws; simpl.
        finish honing.

      simpl in *; intuition.
      rewrite H1; reflexivity.
      apply for_all_add_true; relational.
        rewrite <- H1.
        destruct d.
        eapply allocations_no_overlap_r; eauto.
          exact (proj2_sig r_o).
        rewrite H1.
        eapply for_all_impl; eauto; relational; intros.
        nomega.
      split.
        eapply for_all_impl; eauto; relational; intros.
        nomega.
      nomega.
    }

    repeat breakdown; simpl in *.
    rewrite H0.
    eapply for_all_impl; eauto;
    relational; nomega.
  }

  refine method freeS.
  {
    remove_dependency free_fromADT.

    refine pick val (fst r_n,
                     {| resvs := M.remove d (resvs (snd r_n))
                      ; bytes := bytes (snd r_n) |}).
      simplify with monad laws; simpl.
      finish honing.

    simpl in *; intuition.
    - rewrite H1; reflexivity.
    - apply for_all_remove; relational.
  }

  refine method reallocS.
  {
    unfold find_free_block.
    remove_dependency realloc_fromADT.

    refine pick val (Ifopt M.find d (resvs (snd r_n)) as sz
                     Then If ` d0 <=? sz Then d Else fst r_n
                     Else fst r_n).
    {
      simplify with monad laws.

      refine pick val
        (Ifopt M.find d (resvs (snd r_n)) as sz
         Then If ` d0 <=? sz
              Then
                (fst r_n,
                 {| resvs := M.add d (` d0) (resvs (snd r_n)) (* update *)
                  ; bytes := bytes (snd r_n) |})
              Else
                (fst r_n + ` d0,
                 {| resvs := M.add (fst r_n) (` d0)
                                   (M.remove d (resvs (snd r_n)))
                  ; bytes := copy_bytes d (fst r_n) sz
                                        (bytes (snd r_n)) |})
         Else
           (fst r_n + ` d0,
            {| resvs := M.add (fst r_n) (` d0) (resvs (snd r_n))
             ; bytes := bytes (snd r_n) |})).
        simplify with monad laws.
        finish honing.

      simpl in *; intuition; rewrite ?H1;
      (destruct (M.find d _) as [sz|] eqn:Heqe;
       [ destruct (` d0 <=? sz) eqn:Heqe1;
         simpl; rewrite ?Heqe1 |]); simpl.
      - rewrite remove_add; reflexivity.
      - reflexivity.
      - apply F.add_m; auto.
        apply F.Equal_mapsto_iff; split; intros.
          simplify_maps.
        simplify_maps; intuition.
        subst.
        apply F.find_mapsto_iff in H2.
        congruence.
      - rewrite copy_bytes_idem; assumption.
      - rewrite N.min_l.
          rewrite H0; reflexivity.
        nomega.
      - assumption.
      - normalize.
        apply_for_all; relational.
        rewrite <- remove_add.
        apply for_all_add_true; relational.
          simplify_maps.
        split.
          apply for_all_remove; relational.
        nomega.
      - normalize.
        apply_for_all; relational.
        rewrite <- remove_add.
        apply for_all_add_true; relational.
          simplify_maps.
        split.
          apply for_all_remove; relational.
          apply for_all_remove; relational.
          eapply for_all_impl; eauto;
          relational; nomega.
        nomega.
      - rewrite <- remove_add.
        apply for_all_add_true; relational.
          simplify_maps.
        split.
          apply for_all_remove; relational.
          eapply for_all_impl; eauto;
          relational; nomega.
        nomega.
    }
    simpl in *; intuition; rewrite ?H1;
    (destruct (M.find d _) as [sz|] eqn:Heqe;
     [ destruct (` d0 <=? sz) eqn:Heqe1;
       simpl; rewrite ?Heqe1 |]); simpl.
    - normalize.
      rewrite <- H1 in Heqe.
      pose proof (allocations_no_overlap (proj2_sig r_o) Heqe).
      apply P.for_all_iff; relational; intros.
      simplify_maps.
      rewrite <- H1 in H6.
      specialize (H2 _ _ H6 H5).
      nomega.
    - normalize.
      apply_for_all; relational.
      apply for_all_remove; relational.
      eapply for_all_impl; eauto;
      relational; nomega.
    - apply for_all_remove; relational.
      eapply for_all_impl; eauto;
      relational; nomega.
  }

  refine method peekS.
  {
    remove_dependency peek_fromADT.

    refine pick val (Ifopt M.find d (bytes (snd r_n)) as v
                     Then v
                     Else Zero).
    {
      simplify with monad laws.
      refine pick val r_n.
        simplify with monad laws.
        finish honing.
      simpl in *; intuition.
    }
    simpl in *; intuition.
    destruct (M.find d _) as [sz|] eqn:Heqe;
    simpl; normalize.
      rewrite H0 in H2.
      pose proof (F.MapsTo_fun Heqe H2).
      assumption.
    rewrite H0 in H2.
    apply F.find_mapsto_iff in H2.
    congruence.
  }

  refine method pokeS.
  {
    remove_dependency poke_fromADT.

    refine pick val (fst r_n,
                     {| resvs := resvs (snd r_n)
                      ; bytes := M.add d d0 (bytes (snd r_n)) |}).
      simplify with monad laws.
      finish honing.

    simpl in *; intuition;
    destruct (d <? fst r_n) eqn:Heqe; simpl; trivial;
    rewrite H0; reflexivity.
  }

  refine method memcpyS.
  {
    remove_dependency memcpy_fromADT.

    refine pick val (fst r_n,
                     {| resvs := resvs (snd r_n)
                      ; bytes := copy_bytes d d0 d1 (bytes (snd r_n)) |}).
      simplify with monad laws.
      finish honing.

    simpl in *; intuition;
    rewrite H0; reflexivity.
  }

  refine method memsetS.
  {
    remove_dependency memset_fromADT.

    refine pick val
       (fst r_n,
        {| resvs := resvs (snd r_n)
         ; bytes :=
             P.update (bytes (snd r_n))
                      (N.peano_rect (fun _ => M.t Word)
                                    (bytes (snd r_n))
                                    (fun i => M.add (d + i)%N d1) d0) |}).
      simplify with monad laws.
      finish honing.

    simpl in *; intuition.
    apply P.update_m; trivial.
    induction d0 using N.peano_ind; simpl; trivial.
    rewrite !N.peano_rect_succ.
    apply F.add_m; trivial.
  }

  finish_SharpeningADT_WithoutDelegation.
Defined.

End HeapCanonical.
