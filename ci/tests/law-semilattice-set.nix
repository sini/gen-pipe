# law-semilattice-set (E10 retired → the real class). `merge = "semilattice-set"` is an idempotent
# set-union channel discipline: duplicate contribution VALUES collapse (dedup by `==`), so re-contributing
# an already-present value is a no-op — the ACI convergence of a join-semilattice (Arntzenius &
# Krishnaswami's Datafun fixpoint restriction; Shapiro et al.'s CRDTs). The class is OPT-IN — a channel
# declares `merge = "semilattice-set"` to get it; the default `ordered-list` discipline is unchanged.
#
# RESULT ORDER: FIRST-OCCURRENCE (pinned-order stable) — the earliest occurrence of each distinct value
# survives in place; a later duplicate is dropped. The result is thus a set whose iteration order is the
# pinned contribution order of first appearances (documented + pinned below).
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) contribHost;
  inherit (genPipe)
    channel
    compose
    run
    ;

  # a semilattice-set channel (opt-in via the merge discipline — no explicit combine/init/dedup).
  setChan = channel {
    name = "s";
    merge = "semilattice-set";
  };
  runSet =
    contribs:
    run {
      dag = compose [ setChan ];
      traversal = f.mkTraversal { table.p.s = contribs; };
    };
  valuesOf = out: (out.at "p").s.values;

  # contributions carrying DUPLICATE values (["a"] twice) + distinct values (["b"], ["c"]).
  cA1 = contribHost {
    channel = setChan;
    value = [ "a" ];
    aspect = "x";
  };
  cB = contribHost {
    channel = setChan;
    value = [ "b" ];
    aspect = "y";
  };
  cA2 = contribHost {
    channel = setChan;
    value = [ "a" ];
    aspect = "z";
  }; # a DUPLICATE value of cA1 (distinct producer)
  cC = contribHost {
    channel = setChan;
    value = [ "c" ];
    aspect = "w";
  };

  # the folded set over [ a, b, a, c ] — the second `a` collapses (idempotent set-union).
  folded = valuesOf (runSet [
    cA1
    cB
    cA2
    cC
  ]);
  # the same VALUE multiset in a DIFFERENT contribution order — the RESULT SET is the same set.
  foldedPermuted = valuesOf (runSet [
    cC
    cA2
    cB
    cA1
  ]);
  # re-contributing an already-present value is a no-op (idempotence witnessed on the value level).
  foldedIdempotent = valuesOf (runSet [
    cA1
    cA2
  ]);

  # OVERRIDE PRECEDENCE: a semilattice-set channel with an EXPLICIT dedup policy uses the CALLER's policy,
  # not the class default (value-keyed). Here the caller declares identity dedup (by producer), so two
  # DISTINCT-value contributions from the SAME producer identity collapse to one (identity keep=first) —
  # the value-keyed class default would instead keep both (distinct values). The override wins.
  overrideChan = channel {
    name = "s";
    merge = "semilattice-set";
    dedup = {
      key = "identity";
      keep = "first";
    };
  };
  ovA = contribHost {
    channel = overrideChan;
    value = [ "a" ];
    h = "h1";
    aspect = "same";
  };
  ovB = contribHost {
    channel = overrideChan;
    value = [ "b" ];
    h = "h1";
    aspect = "same";
  }; # SAME (entity, scope, aspect) ⇒ same identity key as ovA; distinct VALUE
  overrideFolded =
    (
      (run {
        dag = compose [ overrideChan ];
        traversal = f.mkTraversal {
          table.p.s = [
            ovA
            ovB
          ];
        };
      }).at
      "p"
    ).s.values;

  # the SECOND E10 firing point (compose.nix re-validation of a hand-built record): a bare record whose
  # `merge = "semilattice-set"` must compose WITHOUT throwing (both former-throw sites accept the class).
  handBuilt = setChan // {
    name = "s";
  };
  composeHandBuilt = compose [ handBuilt ];
in
{
  flake.tests.law-semilattice-set = {
    # the class folds to a SET: the duplicate `["a"]` collapses; result is first-occurrence order.
    test-set-semantics-first-occurrence = {
      expr = folded;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    # ORDER-INDEPENDENCE OF THE RESULT SET: permuting the contribution order yields the SAME set (as a
    # set — sorted here to compare set-equality independent of first-occurrence order).
    test-set-order-independent = {
      expr = builtins.sort (a: b: a < b) folded == builtins.sort (a: b: a < b) foldedPermuted;
      expected = true;
    };
    # IDEMPOTENCE: contributing a value already present adds nothing (the set is unchanged).
    test-set-idempotent = {
      expr = foldedIdempotent;
      expected = [ "a" ];
    };
    # channel CONSTRUCTION accepts the class (the first former-throw site — validateMerge no longer E10s).
    test-construction-accepts-class = {
      expr = setChan.merge;
      expected = "semilattice-set";
    };
    # compose RE-VALIDATION accepts a hand-built semilattice-set record (the second former-throw site).
    test-compose-revalidation-accepts-class = {
      expr = (builtins.tryEval (builtins.deepSeq composeHandBuilt null)).success;
      expected = true;
    };
    # OVERRIDE PRECEDENCE: an explicit dedup on a semilattice-set channel WINS over the class default. Two
    # distinct-value contributions from the same producer identity collapse under the caller's identity
    # dedup (one survivor, value ["a"]) — the value-keyed class default would have kept both distinct values.
    test-override-dedup-precedence = {
      expr = overrideFolded;
      expected = [ "a" ];
    };
  };
}
