# law-tee-order (L3). map preserves order; filter preserves relative order; each tee output (and
# route's delivery) is an order-preserving subsequence of its source; scan emits in input order,
# exactly one output per input (init never emitted, empty input ⇒ empty output). route ≡ unary tee.
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
    scan
    route
    tee
    compose
    run
    sel
    ;

  src = channel { name = "src"; };
  keepA = channel { name = "keepA"; };
  routed = channel { name = "routed"; };
  teed = channel { name = "teed"; };

  # source: three contributions from distinct entities (so selectors can partition them)
  mk =
    ent: v:
    contribHost {
      channel = src;
      value = [ v ];
      h = ent;
      aspect = v;
    };
  table.p.src = [
    (mk "h1" "x1")
    (mk "h2" "x2")
    (mk "h3" "x3")
  ];
  traversal = f.mkTraversal { inherit table; };

  mapped = map (vs: builtins.map (x: x + "!") vs) src;
  filtered = filter (view: view.value != [ "x2" ]) src; # drops the middle one, order preserved
  scanned = scan {
    f = a: b: a ++ b;
    init = [ ];
  } src;

  # route: selective copy of h1's contribution into `routed`
  rt = route {
    from = src;
    select = sel.entity (f.host "h1");
    to = routed;
  };
  # tee with two outputs: catch-all into teed, and h3-only into keepA
  tt = tee {
    from = src;
    outputs = [
      {
        select = sel.all;
        to = teed;
      }
      {
        select = sel.entity (f.host "h3");
        to = keepA;
      }
    ];
  };

  out = run {
    dag = compose [
      src
      keepA
      routed
      teed
      mapped
      filtered
      scanned
      rt
      tt
    ];
    inherit traversal;
  };
  vals = name: (out.at "p").${name}.values;
in
{
  flake.tests.law-tee-order = {
    test-map-preserves-order = {
      expr = vals "src.map.4";
      expected = [
        "x1!"
        "x2!"
        "x3!"
      ];
    };
    test-filter-preserves-relative-order = {
      expr = vals "src.filter.5";
      expected = [
        "x1"
        "x3"
      ];
    };
    # scan: n inputs ⇒ n outputs; k-th = fold of first k; init never emitted
    test-scan-arity-and-order = {
      expr = vals "src.scan.6";
      # each scan output value is a folded list; the channel value concatenates them:
      # [x1] ++ [x1,x2] ++ [x1,x2,x3]
      expected = [
        "x1"
        "x1"
        "x2"
        "x1"
        "x2"
        "x3"
      ];
    };
    # route delivers h1 only, preserving source order (single element here)
    test-route-subsequence = {
      expr = vals "routed";
      expected = [ "x1" ];
    };
    # tee catch-all output = order-preserving full subsequence of the source
    test-tee-catchall-order = {
      expr = vals "teed";
      expected = [
        "x1"
        "x2"
        "x3"
      ];
    };
    # tee selective output = h3 only
    test-tee-selective = {
      expr = vals "keepA";
      expected = [ "x3" ];
    };
  };
}
