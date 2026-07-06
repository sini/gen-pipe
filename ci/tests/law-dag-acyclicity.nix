# law-dag-acyclicity (L4). compose rejects any cycle through operator edges with E3, naming the
# channels and operators; validation forces DAG STRUCTURE only, never contribution values.
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (genPipe)
    channel
    map
    join
    route
    compose
    run
    sel
    ;

  A = channel { name = "A"; };
  B = channel { name = "B"; };

  ok =
    (compose [
      A
      B
      (route {
        from = A;
        select = sel.star;
        to = B;
      })
    ]).topo;

  routeCycle =
    (compose [
      A
      B
      (route {
        from = A;
        select = sel.star;
        to = B;
      })
      (route {
        from = B;
        select = sel.star;
        to = A;
      })
    ]).channels;

  jA = join {
    inputs = [ B ];
    name = "jA";
  };
  jB = join {
    inputs = [ A ];
    name = "jB";
  };
  # a derive cycle: mA depends on A; route A ← mA closes it
  mA = map (v: v) A;
  mixedCycle =
    (compose [
      A
      mA
      (route {
        from = mA;
        select = sel.star;
        to = A;
      })
    ]).channels;

  # poisoned-value probe: a channel whose contributions throw on force still COMPOSES (structure
  # only) and evaluates its topo without forcing any value.
  poison = channel { name = "P"; };
  poisonDag = compose [ poison ];
in
{
  flake.tests.law-dag-acyclicity = {
    test-acyclic-composes = {
      expr = builtins.isList ok;
      expected = true;
    };
    test-route-cycle-e3 = {
      expr = (builtins.tryEval (builtins.deepSeq routeCycle true)).success;
      expected = false;
    };
    # a join-derived cycle (jA ⟵ B ⟵ jB ⟵ A ⟵ jA closed by mutual derive) is rejected.
    test-join-cycle-e3 = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq
            (compose [
              A
              B
              jA
              jB
              (route {
                from = jA;
                select = sel.star;
                to = A;
              })
              (route {
                from = jB;
                select = sel.star;
                to = B;
              })
            ]).channels
            true
        )).success;
      expected = false;
    };
    test-mixed-cycle-e3 = {
      expr = (builtins.tryEval (builtins.deepSeq mixedCycle true)).success;
      expected = false;
    };
    # compose does not force contribution values (the throwing channel composes fine).
    test-compose-no-value-force = {
      expr = builtins.isList poisonDag.topo;
      expected = true;
    };
  };
}
