# law-deferred (L9). `deferred` marks a config-demanding value; its `value` field is a poisoned E6
# thunk until resolution. `map` composes into the thunk (f applies post-resolution). Value-demanding
# operators/selectors touching an unresolved deferred value throw E6. The resolution environment is
# the producing class's config at the producing scope, filtered to the fn's demanded args; both
# resolution routes (resolve-at-source values / deferred-to-consumer records) yield identical values.
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) host clsNixos clsHm;
  inherit (genPipe)
    channel
    contribute
    deferred
    map
    filter
    fold
    compose
    run
    consume
    ;

  ch = channel { name = "c"; };
  hostPos = {
    entity = host "axon-01";
    scope.host = host "axon-01";
    aspect = f.aspect "A";
    classes = [ clsNixos ];
  };

  # a deferred contribution demanding config only (root-class producer → no parentArg)
  dc = contribute {
    channel = ch;
    value = deferred ({ config }: [ config.v ]);
    producer = hostPos;
  };
  # a deferred contribution demanding config + osConfig (nested-class producer → parentArg)
  dcNested = contribute {
    channel = ch;
    value = deferred ({ config, osConfig }: [ (config.v + osConfig.v) ]);
    class = clsHm;
    producer = {
      entity = host "axon-01";
      scope = {
        host = host "axon-01";
        user = f.user "sini";
      };
      aspect = f.aspect "A";
      classes = [ clsHm ];
    };
  };

  # stub resolver (resolve-at-source): builds the §2.6.4 environment and filters it to the fn's
  # demanded args (via the contribution's argDemand), then applies the composed fn.
  env = {
    config.v = "C";
    osConfig.v = "O";
    host = host "axon-01";
    lib = { };
  };
  resolveDeferred = c: c.fn (builtins.intersectAttrs c.argDemand env);

  mapped = map (vs: vs ++ [ "!" ]) ch;
  dag = compose [
    ch
    mapped
  ];

  outVals = run {
    inherit dag;
    traversal = f.mkTraversal {
      table.p.c = [ dc ];
      inherit resolveDeferred;
    };
  };
  outNoResolver = run {
    inherit dag;
    traversal = f.mkTraversal { table.p.c = [ dc ]; };
  };

  # resolve-at-source (values) of the mapped channel: f ∘ fn under the env
  valuesRoute = consume {
    outputs = outVals;
    at = "p";
    channel = mapped;
    class = clsNixos;
    mode = "values";
  };
  # deferred-to-consumer (records): resolve in the "consumer" with the same env
  recordsRoute = consume {
    outputs = outVals;
    at = "p";
    channel = mapped;
    class = clsNixos;
    mode = "records";
  };
  recordResolved = builtins.map (
    r: r.resolve (builtins.intersectAttrs r.contribution.argDemand env)
  ) recordsRoute;

  tri = builtins.tryEval;
  # E6 probes: operators/selectors that force .value of an unresolved deferred contribution.
  filterTouch = filter (view: view.value == [ "x" ]) ch;
  foldTouch = fold {
    f = a: b: a ++ b;
    init = [ ];
  } ch;
  e6dag = compose [
    ch
    filterTouch
    foldTouch
  ];
  e6out = run {
    dag = e6dag;
    traversal = f.mkTraversal { table.p.c = [ dc ]; };
  };
in
{
  flake.tests.law-deferred = {
    # map composes into the thunk: after resolution, f(fn env) = ["C"] ++ ["!"].
    test-map-composes-into-thunk = {
      expr = builtins.head valuesRoute;
      expected = [
        "C"
        "!"
      ];
    };
    # environment shape: fn receives config filtered to its demand (root-class, config only).
    test-env-root-config-only = {
      expr = resolveDeferred dc;
      expected = [ "C" ];
    };
    # nested producer: fn receives config + osConfig (parentArg).
    test-env-nested-parentarg = {
      expr = resolveDeferred dcNested;
      expected = [ "CO" ];
    };
    # route-parity: resolve-at-source (values) == deferred-to-consumer (records).
    test-route-parity = {
      expr = valuesRoute == recordResolved;
      expected = true;
    };
    # value-mode read with no resolver present and a deferred contribution ⇒ E11.
    test-e11-no-resolver = {
      expr =
        (tri (
          builtins.deepSeq (consume {
            outputs = outNoResolver;
            at = "p";
            channel = mapped;
            class = clsNixos;
            mode = "values";
          }) true
        )).success;
      expected = false;
    };
    # filter touching .value of an unresolved deferred contribution ⇒ E6.
    test-e6-filter-touch = {
      expr = (tri (e6out.at "p")."c.filter.1".contributions).success;
      expected = false;
    };
    # fold forcing an unresolved deferred value ⇒ E6.
    test-e6-fold-touch = {
      expr = (tri (e6out.at "p")."c.fold.2".values).success;
      expected = false;
    };
  };
}
