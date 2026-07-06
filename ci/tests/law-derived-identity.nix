# law-derived-identity (L12). Deriving operators return channels with declaration-default attributes
# — merge/combine/dedup/type/class are never inherited; contracts apply to a derived channel only by
# explicit record-form re-declaration. Derived identity is deterministic: explicit `name`, or the
# "<input>.<op>.<declIndex>" scheme; E4b governs uniqueness either way.
{
  lib,
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) host contribHost;
  inherit (genPipe)
    channel
    map
    filter
    fold
    join
    compose
    run
    ;

  base = channel {
    name = "base";
    dedup = {
      key = "identity";
      keep = "first";
    };
  };
  mapped = map (v: v) base;
  filtered = filter (_: true) base;
  folded = fold {
    f = a: b: a ++ b;
    init = [ ];
  } base;
  joined = join {
    inputs = [
      base
      mapped
    ];
  };

  dagAuto = compose [
    base
    mapped
    filtered
    folded
    joined
  ];

  # explicit record-form name + re-declared dedup on a derived channel
  namedMapped = map {
    f = v: v;
    name = "renamed";
    dedup = {
      key = "identity";
      keep = "last";
    };
  } base;
  dagNamed = compose [
    base
    namedMapped
  ];
in
{
  flake.tests.law-derived-identity = {
    # deterministic derived names "<input>.<op>.<declIndex>"
    test-map-derived-name = {
      expr = builtins.attrNames dagAuto.channels;
      expected = [
        "base"
        "base.filter.2"
        "base.fold.3"
        "base.map.1"
        "join.4"
      ];
    };
    test-map-name-scheme = {
      expr = dagAuto.channels ? "base.map.1";
      expected = true;
    };
    test-join-name-scheme = {
      expr = dagAuto.channels ? "join.4";
      expected = true;
    };

    # attribute reset (L12): the derived channel does NOT inherit the input's dedup.
    test-derived-dedup-reset = {
      expr = dagAuto.channels."base.map.1".dedup;
      expected = null;
    };
    test-derived-merge-default = {
      expr = dagAuto.channels."base.map.1".merge;
      expected = "ordered-list";
    };
    test-derived-class-reset = {
      expr = dagAuto.channels."base.map.1".class.adapters;
      expected = [ ];
    };

    # explicit record-form name wins, and a re-declared dedup applies to the derived channel.
    test-explicit-name = {
      expr = dagNamed.channels ? "renamed";
      expected = true;
    };
    test-redeclared-dedup = {
      expr = dagNamed.channels.renamed.dedup.keep;
      expected = "last";
    };

    # explicit-vs-derived name collision ⇒ E4b.
    test-name-collision-e4b = {
      expr =
        let
          collide = map {
            f = v: v;
            name = "base.map.1";
          } base;
          r =
            builtins.tryEval
              (compose [
                base
                (map (v: v) base) # → base.map.1
                collide # explicit "base.map.1" → collision
              ]).channels;
        in
        r.success;
      expected = false;
    };
  };
}
