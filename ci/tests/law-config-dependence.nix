# law-config-dependence (L13). Every contribution and derived-channel output carries a static
# `classInvariant` flag derived from arg-shape: deferred (config-demanding) ⇒ false (per-member by
# construction); non-deferred ⇒ true (config-independent, E8-sound). The flag composes through
# operators monotonically and is computable WITHOUT forcing any contribution value.
{
  lib,
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) host clsNixos;
  inherit (genPipe)
    channel
    contribute
    deferred
    map
    filter
    fold
    scan
    join
    compose
    run
    ;

  ch = channel { name = "c"; };

  # a plain (class-invariant candidate) contribution and a deferred (per-member) one
  plain =
    v:
    contribute {
      channel = ch;
      value = [ v ];
      producer = {
        entity = host "axon-01";
        scope = {
          host = host "axon-01";
        };
        aspect = null;
      };
    };
  defer = contribute {
    channel = ch;
    value = deferred ({ config }: [ config.x ]);
    class = clsNixos;
    producer = {
      entity = host "axon-01";
      scope = {
        host = host "axon-01";
      };
      aspect = null;
      classes = [ clsNixos ];
    };
  };

  mkOut =
    { table, dag }:
    run {
      inherit dag;
      traversal = f.mkTraversal { inherit table; };
    };

  # ── single-channel flags ──
  chDag = compose [ ch ];
  flagsAt =
    contribs:
    (
      (run {
        dag = chDag;
        traversal = f.mkTraversal { table.p.c = contribs; };
      }).at
      "p"
    ).c.classInvariant;

  # ── operator taint ──
  mapped = map (v: v) ch;
  # config-reading map fn ⇒ taints to false. Explicit name: a distinct map over the same input
  # needs its own identity (the "<input>.<op>" base id would otherwise collide, L12/§2.3a).
  mappedCfg = map {
    f = { config }: config;
    name = "mappedCfg";
  } ch;
  filtered = filter (_: true) ch;
  folded = fold {
    f = a: b: a ++ b;
    init = [ ];
  } ch;

  taintDag = compose [
    ch
    mapped
    mappedCfg
    filtered
    folded
  ];
  taintOut =
    contribs:
    (run {
      dag = taintDag;
      traversal = f.mkTraversal { table.p.c = contribs; };
    }).at
      "p";

  # poisoned-value probe: partition succeeds over a channel whose deferred value throws E6 on force.
  probeFlags = flagsAt [
    (plain "a")
    defer
  ];
in
{
  flake.tests.law-config-dependence = {
    # arg-shape derivation
    test-plain-invariant = {
      expr = flagsAt [ (plain "a") ];
      expected = [ true ];
    };
    test-deferred-not-invariant = {
      expr = flagsAt [ defer ];
      expected = [ false ];
    };
    test-mixed-partition = {
      expr = probeFlags;
      expected = [
        true
        false
      ];
    };
    # the partition above was computed without forcing values — prove the deferred value DOES throw.
    test-poisoned-value-throws = {
      expr =
        (builtins.tryEval
          (
            (run {
              dag = chDag;
              traversal = f.mkTraversal { table.p.c = [ defer ]; };
            }).at
            "p"
          ).c.values
        ).success;
      expected = false;
    };

    # map with a config-free f preserves the per-contribution flag.
    test-map-preserves = {
      expr = (taintOut [ (plain "a") ])."c.map.1".classInvariant;
      expected = [ true ];
    };
    # map with a config-reading f taints the output to false.
    test-map-config-taints = {
      expr = (taintOut [ (plain "a") ])."mappedCfg".classInvariant;
      expected = [ false ];
    };
    # filter preserves the flag (metadata predicate).
    test-filter-preserves = {
      expr = (taintOut [ (plain "a") ])."c.filter.3".classInvariant;
      expected = [ true ];
    };
    # fold over all-invariant inputs with a config-free f ⇒ invariant.
    test-fold-all-invariant = {
      expr =
        (taintOut [
          (plain "a")
          (plain "b")
        ])."c.fold.4".classInvariant;
      expected = [ true ];
    };
    # one per-member (deferred) input taints the fold output to false — WITHOUT forcing its value.
    test-fold-one-permember-taints = {
      expr =
        (taintOut [
          (plain "a")
          defer
        ])."c.fold.4".classInvariant;
      expected = [ false ];
    };
  };
}
