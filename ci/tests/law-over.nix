# law-over (§2.3, L12/L13). `over f` applies `f` to a channel's WHOLE contribution-value list at once
# (`f : [a] -> [b]`), re-seeding each result element as a fresh contribution. map/filter/fold/scan are
# the STRUCTURED list operators (Bird–Meertens `map`/catamorphism/`scan`, each with a fusion law and a
# value-independent output shape); `over` is the UNSTRUCTURED general list function — the escape hatch
# for whole-list rewrites (reverse, take, cross-element rewrite) no structured operator expresses.
#
# It is value-demanding like fold/scan, but STRICTER: its output cardinality is `length (f values)`, so
# a deferred input poisons even the contribution STRUCTURE (E6), where fold keeps its single output
# readable. classInvariant composes exactly as fold's (all inputs invariant ∧ f config-free — L13).
{
  lib,
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) contribHost;
  inherit (genPipe)
    channel
    contribute
    deferred
    map
    over
    compose
    run
    ;

  base = channel { name = "base"; };
  c =
    v:
    contribHost {
      channel = base;
      value = v;
    };
  # three plain (class-invariant) list-valued contributions at one position
  table.p.base = [
    (c [ "a" ])
    (c [ "b" ])
    (c [ "c" ])
  ];
  trav = f.mkTraversal { inherit table; };

  # reverse: each output's POSITION depends on the whole list — a per-element `map` cannot express it.
  revd = over (xs: lib.reverseList xs) base;
  revOut = run {
    dag = compose [
      base
      revd
    ];
    traversal = trav;
  };

  # same input through per-element identity `map` — the divergence witness (map keeps order).
  ident = map (v: v) base;
  mapOut = run {
    dag = compose [
      base
      ident
    ];
    traversal = trav;
  };

  # cardinality change N -> 1: collapse the whole list into a single contribution.
  collapsed = over (xs: [ (lib.concatLists xs) ]) base;
  colOut = run {
    dag = compose [
      base
      collapsed
    ];
    traversal = trav;
  };

  # a deferred (config-demanding) input: `over` is value-demanding, so forcing it pre-resolution is E6.
  dfr = contribute {
    channel = base;
    value = deferred ({ config }: [ config.v ]);
    producer = f.hostProducer { h = "axon-01"; };
  };
  e6Over = over (xs: xs) base;
  e6Out = run {
    dag = compose [
      base
      e6Over
    ];
    traversal = f.mkTraversal {
      table.p.base = [
        (c [ "a" ])
        dfr
      ];
    };
  };

  tri = builtins.tryEval;
in
{
  flake.tests.law-over = {
    # whole-list semantics: the channel value is the reversed contribution order.
    test-whole-list-reverse = {
      expr = (revOut.at "p")."base.over.1".values;
      expected = [
        "c"
        "b"
        "a"
      ];
    };
    # divergence from `map`: the SAME input through per-element identity keeps declaration order, so
    # `over reverseList` is observably not a `map` (the whole point of the op).
    test-diverges-from-map = {
      expr = (mapOut.at "p")."base.map.1".values;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    # cardinality change: N inputs -> 1 output contribution (impossible for map/filter).
    test-cardinality-collapse-count = {
      expr = builtins.length (colOut.at "p")."base.over.1".contributions;
      expected = 1;
    };
    test-cardinality-collapse-value = {
      expr = (colOut.at "p")."base.over.1".values;
      expected = [
        "a"
        "b"
        "c"
      ];
    };
    # L12 derived identity: bare-fn `over` names the node "<input>.over.<declIndex>".
    test-derived-name = {
      expr = builtins.hasAttr "base.over.1" (revOut.at "p");
      expected = true;
    };
    # L13 classInvariant: pure `f` over class-invariant inputs stays class-invariant, per output.
    test-classinvariant = {
      expr = (revOut.at "p")."base.over.1".classInvariant;
      expected = [
        true
        true
        true
      ];
    };
    # provenance: each output is re-seeded with a single `over` hop referencing the WHOLE input batch.
    test-provenance-batch-hop = {
      expr =
        let
          hop = builtins.head (builtins.head (revOut.at "p")."base.over.1".contributions).provenance.hops;
        in
        {
          inherit (hop) op channel;
          inputs = builtins.length hop.inputs;
        };
      expected = {
        op = "over";
        # hop.channel is the DERIVED channel's own final name (as fold/scan record theirs), not the input.
        channel = "base.over.1";
        inputs = 3;
      };
    };
    # value-demanding: forcing `over`'s value over an unresolved deferred input ⇒ E6.
    test-e6-values = {
      expr = (tri (e6Out.at "p")."base.over.1".values).success;
      expected = false;
    };
    # STRICTER than fold/scan: `over`'s output cardinality is value-dependent, so even the contribution
    # STRUCTURE forces the deferred guard (fold keeps its single output readable; `over` does not).
    test-e6-contributions-strict = {
      expr = (tri (builtins.deepSeq (e6Out.at "p")."base.over.1".contributions true)).success;
      expected = false;
    };
  };
}
