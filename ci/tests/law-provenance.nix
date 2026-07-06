# law-provenance (L8). Every contribution carries structured producer identity (entity entry, scope
# coordinate entries, aspect entry) from emission; every operator/adapter/resolution appends a
# structured hop; provenanceOf recovers the full chain from any contribution or consumption record.
# Bare scalar values carry no provenance — recovery goes through the paired record.
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
    fold
    route
    compose
    run
    provenanceOf
    sel
    ;

  src = channel { name = "src"; };
  sink = channel { name = "sink"; };
  c0 = contribHost {
    channel = src;
    value = [ "v" ];
    h = "axon-01";
    aspect = "myAspect";
  };

  mapped = map (v: v) src;
  folded = fold {
    f = a: b: a ++ b;
    init = [ ];
  } src;
  rt = route {
    from = src;
    select = sel.all;
    to = sink;
  };

  out = run {
    dag = compose [
      src
      sink
      mapped
      folded
      rt
    ];
    traversal = f.mkTraversal { table.p.src = [ c0 ]; };
  };
  at = name: builtins.head (out.at "p").${name}.contributions;
  chain = name: provenanceOf (at name);
in
{
  flake.tests.law-provenance = {
    # base record carries entries with id_hash.
    test-base-entity-id = {
      expr = (chain "src").base.producer.entity.id_hash;
      expected = "h:host:axon-01";
    };
    test-base-aspect-id = {
      expr = (chain "src").base.producer.aspect.id_hash;
      expected = "h:aspect:myAspect";
    };
    # base contribution has no hops.
    test-base-no-hops = {
      expr = (chain "src").hops;
      expected = [ ];
    };
    # map appends a hop naming the operator + channel.
    test-map-hop = {
      expr = builtins.map (h: h.op) (chain "src.map.2").hops;
      expected = [ "map" ];
    };
    # route delivery appends a route hop naming from → to.
    test-route-hop = {
      expr =
        let
          h = builtins.head (chain "sink").hops;
        in
        {
          inherit (h) op from to;
        };
      expected = {
        op = "route";
        from = "src";
        to = "sink";
      };
    };
    # fold output lists its inputs in the fold hop.
    test-fold-inputs-listed = {
      expr =
        let
          h = builtins.head (chain "src.fold.3").hops;
        in
        {
          inherit (h) op;
          n = builtins.length h.inputs;
        };
      expected = {
        op = "fold";
        n = 1;
      };
    };
    # synthetic fold output carries a null-entity base (folded data is class-neutral).
    test-fold-synthetic-base = {
      expr = (chain "src.fold.3").base.producer.entity;
      expected = null;
    };
    # provenanceOf rejects a non-record.
    test-provenanceof-domain = {
      expr =
        (builtins.tryEval (provenanceOf {
          not = "a record";
        })).success;
      expected = false;
    };
  };
}
