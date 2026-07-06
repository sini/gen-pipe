# law-b5-ordering (L1). A channel's value at a position is the left fold of its contributions in the
# pinned canonical traversal (self → imports → parent; imports in declaration order) under the
# associative-only combine. The pin is the public, stable contract. Swapping a commutative/idempotent
# combine into an ordered-list channel is a correctness regression, not an optimization — this suite
# would catch it.
{
  lib,
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) host;
  inherit (genPipe)
    channel
    contribute
    compose
    run
    ;

  ch = channel { name = "seq"; };

  cv =
    v: pos:
    contribute {
      channel = ch;
      value = [ v ];
      producer = {
        entity = host pos;
        scope = {
          host = host pos;
        };
        aspect = null;
      };
    };

  # visibility pin: self → imports (declaration order) → parent
  visibility = [
    "self"
    "imp1"
    "imp2"
    "parent"
  ];
  table = {
    self.seq = [ (cv "SELF" "self") ];
    imp1.seq = [ (cv "IMP1" "imp1") ];
    imp2.seq = [ (cv "IMP2" "imp2") ];
    parent.seq = [ (cv "PARENT" "parent") ];
  };
  traversal = f.mkTraversal {
    inherit table;
    order = _: visibility;
  };

  dag = compose [ ch ];
  out = run { inherit dag traversal; };
  valAt = (out.at "p").seq.values;

  # A commutative + idempotent (set-like) combine: sorts and dedups. Reordering/dedup is exactly the
  # B5 regression — the ordered channel MUST NOT behave this way.
  setCh = channel {
    name = "setseq";
    combine = a: b: lib.sort (x: y: x < y) (lib.unique (a ++ b));
    init = [ ];
  };
  cvSet =
    v: pos:
    contribute {
      channel = setCh;
      value = [ v ];
      producer = {
        entity = host pos;
        scope = {
          host = host pos;
        };
        aspect = null;
      };
    };
  setTable = {
    self.setseq = [ (cvSet "PARENT" "self") ];
    imp1.setseq = [ (cvSet "IMP1" "imp1") ];
    imp2.setseq = [ (cvSet "IMP2" "imp2") ];
    parent.setseq = [ (cvSet "SELF" "parent") ];
  };
  setOut = run {
    dag = compose [ setCh ];
    traversal = f.mkTraversal {
      table = setTable;
      order = _: visibility;
    };
  };
in
{
  flake.tests.law-b5-ordering = {
    # Golden pinned-order sequence: self, then imports in declaration order, then parent.
    test-pinned-order = {
      expr = valAt;
      expected = [
        "SELF"
        "IMP1"
        "IMP2"
        "PARENT"
      ];
    };

    # The ordered channel folds in visibility order regardless of value content (non-commutative ++).
    test-order-is-visibility-not-value = {
      expr = builtins.head valAt;
      expected = "SELF";
    };

    # Regression witness: a commutative+idempotent combine REORDERS (and would dedup) — its output
    # differs from the pinned ordered fold. The test proves the divergence is detectable.
    test-set-combine-differs = {
      expr = (setOut.at "p").setseq.values != valAt;
      expected = true;
    };
    # And concretely it sorts (SELF appears last after sort, PARENT first) — the reorder is real.
    test-set-combine-sorts = {
      expr = (setOut.at "p").setseq.values;
      expected = [
        "IMP1"
        "IMP2"
        "PARENT"
        "SELF"
      ];
    };
  };
}
