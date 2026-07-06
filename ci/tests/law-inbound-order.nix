# law-inbound-order (L11). A channel's sequence at a position is its native base followed by its
# inbound route/tee deliveries in compose declaration order of the delivering edges, each an
# order-preserving (select-matched) subsequence of its source at the SAME position — no interleaving,
# no cross-position delivery. Dedup and combine apply once, over the full sequence.
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) contribHost;
  inherit (genPipe)
    channel
    route
    compose
    run
    sel
    traceOf
    ;

  target = channel {
    name = "T";
    dedup = {
      key = "identity";
      keep = "first";
    };
  };
  s1 = channel { name = "S1"; };
  s2 = channel { name = "S2"; };

  # T's native contribution; S1 carries a DUPLICATE of it (same producer identity) + its own; S2 own.
  tNative = contribHost {
    channel = target;
    value = [ "t0" ];
    h = "hT";
    aspect = "aT";
  };
  s1dup = contribHost {
    channel = s1;
    value = [ "t0" ];
    h = "hT";
    aspect = "aT";
  }; # same (entity,scope) as tNative
  s1own = contribHost {
    channel = s1;
    value = [ "s1" ];
    h = "h1";
    aspect = "a1";
  };
  s2own = contribHost {
    channel = s2;
    value = [ "s2" ];
    h = "h2";
    aspect = "a2";
  };

  table.p = {
    T = [ tNative ];
    S1 = [
      s1dup
      s1own
    ];
    S2 = [ s2own ];
  };
  otherP.q = {
    T = [ ];
    S1 = [ ];
    S2 = [ ];
  };
  traversal = f.mkTraversal { table = table // otherP; };

  r1 = route {
    from = s1;
    select = sel.all;
    to = target;
  };
  r2 = route {
    from = s2;
    select = sel.all;
    to = target;
  };

  # native, then r1 deliveries, then r2 deliveries (decls order S1 before S2)
  outAB = run {
    dag = compose [
      target
      s1
      s2
      r1
      r2
    ];
    inherit traversal;
  };
  # permuted route declaration order (r2 before r1) ⇒ different sequence
  outBA = run {
    dag = compose [
      target
      s1
      s2
      r2
      r1
    ];
    inherit traversal;
  };
  valsAB = (outAB.at "p").T.values;
  trace = traceOf {
    outputs = outAB;
    at = "p";
    channel = target;
  };
in
{
  flake.tests.law-inbound-order = {
    # native base, then deliveries in decls order; the delivered duplicate of t0 is deduped away.
    test-native-then-deliveries = {
      expr = valsAB;
      expected = [
        "t0"
        "s1"
        "s2"
      ];
    };
    # permuting the two route declarations is a semantic change: s2 delivery now precedes s1.
    test-permuted-decls-differ = {
      expr = (outBA.at "p").T.values;
      expected = [
        "t0"
        "s2"
        "s1"
      ];
    };
    # dedup applies ONCE over the full (native + delivered) sequence — the duplicate is recorded.
    test-dedup-over-full-sequence = {
      expr = builtins.length trace.deduped;
      expected = 1;
    };
    # routedIn trace entries are in delivery order with their declIndex.
    test-routedin-order = {
      expr = builtins.map (r: {
        inherit (r) from via;
      }) trace.routedIn;
      expected = [
        {
          from = "S1";
          via = "route";
        }
        {
          from = "S2";
          via = "route";
        }
      ];
    };
    # position-locality: at a position with no source contributions, no deliveries arrive.
    test-position-locality = {
      expr = (outAB.at "q").T.values;
      expected = [ ];
    };
  };
}
