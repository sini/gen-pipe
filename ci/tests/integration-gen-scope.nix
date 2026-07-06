# integration-gen-scope (L1, L6). The stub-adapter goldens re-run against a REAL gen-scope graph:
# the traversal `order` (self → imports → parent) is derived from gen-scope's neron collection over an
# actual parent+import graph, so gen-pipe folds in the gen-scope collectionAttr pin. Demand/laziness
# probes ride the same wiring.
{
  genPipe,
  genScope,
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

  # gen-scope graph: self imports imp, self's parent is parent.
  roots = genScope.buildNodes {
    parentGraph = genScope.edge "self" "parent";
    importGraph = genScope.edge "self" "imp";
    decls = {
      self = { };
      imp = { };
      parent = { };
    };
    types = { };
  };

  scope = genScope.eval {
    inherit roots;
    attributes = {
      children =
        _: id:
        builtins.listToAttrs (
          builtins.filter (e: e.value != null) (
            map (n: {
              name = n;
              value = if (roots.${n}.parent or null) == id then roots.${n} else null;
            }) (builtins.attrNames roots)
          )
        );
      imports = self: id: (self.node id).decls.__edges.I or [ ];
      # neron visibility order: self → imports (declaration order) → parent — the pinned collection.
      neron-order = genScope.collectionAttr {
        traverse = "neron";
        extract = _: id: [ id ];
      };
    };
    parseParent = id: (roots.${id} or { parent = null; }).parent;
  };

  # gen-scope-derived pin, fed to gen-pipe as the traversal order.
  neronOrder = pos: scope.get pos "neron-order";

  ch = channel { name = "seq"; };
  sibling = channel { name = "sib"; };
  cv =
    pos:
    contribute {
      channel = ch;
      value = [ pos ];
      producer = {
        entity = host pos;
        scope.host = host pos;
        aspect = null;
      };
    };
  boom = contribute {
    channel = sibling;
    value = throw "gen-pipe-integration: sib forced";
    producer = {
      entity = host "x";
      scope.host = host "x";
      aspect = null;
    };
  };

  traversal = {
    order = neronOrder;
    contributionsAt =
      pos: chName:
      if chName == "seq" then
        [ (cv pos) ]
      else if pos == "self" && chName == "sib" then
        [ boom ]
      else
        [ ];
    classesOf = _: [ ];
    render = c: builtins.toJSON c;
  };

  out = run {
    dag = compose [
      ch
      sibling
    ];
    inherit traversal;
  };
in
{
  flake.tests.integration-gen-scope = {
    # the pin itself comes from gen-scope's neron collection.
    test-neron-order = {
      expr = neronOrder "self";
      expected = [
        "self"
        "imp"
        "parent"
      ];
    };
    # gen-pipe folds contributions in the gen-scope-derived pin (self → imports → parent).
    test-pinned-fold = {
      expr = (out.at "self").seq.values;
      expected = [
        "self"
        "imp"
        "parent"
      ];
    };
    # a leaf position (no imports/parent) sees only itself.
    test-leaf-position = {
      expr = (out.at "parent").seq.values;
      expected = [ "parent" ];
    };
    # demand: consuming `seq` never forces the throwing sibling channel.
    test-demand-sibling-not-forced = {
      expr = (out.at "self").seq.values;
      expected = [
        "self"
        "imp"
        "parent"
      ];
    };
  };
}
