# law-b2-read-only (L5, L10). gen-pipe reads the scope graph through the traversal adapter and
# produces plain data; no output feeds graph structure (B2, van Antwerpen et al. 2016 Statix via
# HOAG r2 §B2). Operators are non-destructive: a channel's value at a position is independent of the
# set of operators/consumers reading it (L10).
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) contribHost;
  inherit (genPipe)
    channel
    map
    filter
    route
    compose
    run
    sel
    ;

  base = channel { name = "base"; };
  sink = channel { name = "sink"; };
  c1 = contribHost {
    channel = base;
    value = [ "a" ];
    h = "h1";
    aspect = "1";
  };
  c2 = contribHost {
    channel = base;
    value = [ "b" ];
    h = "h2";
    aspect = "2";
  };
  table.p.base = [
    c1
    c2
  ];
  traversal = f.mkTraversal { inherit table; };

  # 0 readers
  out0 = run {
    dag = compose [ base ];
    inherit traversal;
  };
  # 1 reader (a map)
  out1 = run {
    dag = compose [
      base
      (map (v: v) base)
    ];
    inherit traversal;
  };
  # N readers (map + filter + route into a sink)
  outN = run {
    dag = compose [
      base
      sink
      (map (v: v) base)
      (filter (_: true) base)
      (route {
        from = base;
        select = sel.all;
        to = sink;
      })
    ];
    inherit traversal;
  };

  valOf = out: (out.at "p").base.values;

  # An adapter that EXPOSES only the declared contract fields; accessing anything else throws. run
  # must touch only order / contributionsAt (+ classesOf/render/resolveDeferred where needed).
  strictTraversal = {
    order = p: [ p ];
    contributionsAt = p: chName: (table.${p} or { }).${chName} or [ ];
    classesOf = _: [ ];
    render = c: "r";
  };
  strictOut = run {
    dag = compose [ base ];
    traversal = strictTraversal;
  };
in
{
  flake.tests.law-b2-read-only = {
    # L10: the base channel's value is identical under 0, 1, and N readers.
    test-value-invariant-0-vs-1 = {
      expr = valOf out0 == valOf out1;
      expected = true;
    };
    test-value-invariant-0-vs-N = {
      expr = valOf out0 == valOf outN;
      expected = true;
    };
    test-value-concrete = {
      expr = valOf outN;
      expected = [
        "a"
        "b"
      ];
    };
    # L5: run consumes only the declared adapter read-surface (no resolveDeferred needed here).
    test-read-surface-minimal = {
      expr = (strictOut.at "p").base.values;
      expected = [
        "a"
        "b"
      ];
    };
  };
}
