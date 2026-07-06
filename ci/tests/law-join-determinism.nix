# law-join-determinism (L2). join's output sequence is the concatenation of its inputs' L1-ordered
# sequences in the pinned `inputs` declaration order; a supplied combine left-folds that pinned
# sequence. compose never reorders inputs — permuting them is a semantic change (witnessed, not
# prevented).
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f) contribHost;
  inherit (genPipe)
    channel
    join
    compose
    run
    ;

  chA = channel { name = "A"; };
  chB = channel { name = "B"; };
  chC = channel { name = "C"; };

  table.p = {
    A = [
      (contribHost {
        channel = chA;
        value = [ "a1" ];
        aspect = "a1";
      })
      (contribHost {
        channel = chA;
        value = [ "a2" ];
        aspect = "a2";
      })
    ];
    B = [
      (contribHost {
        channel = chB;
        value = [ "b1" ];
        aspect = "b1";
      })
    ];
    C = [
      (contribHost {
        channel = chC;
        value = [ "c1" ];
        aspect = "c1";
      })
    ];
  };
  traversal = f.mkTraversal { inherit table; };

  jAB = join {
    inputs = [
      chA
      chB
    ];
    name = "jAB";
  };
  jBA = join {
    inputs = [
      chB
      chA
    ];
    name = "jBA";
  };
  jCombine = join {
    inputs = [
      chA
      chB
    ];
    name = "jCount";
    combine = {
      f = acc: v: acc + builtins.length v;
      init = 0;
    };
  };
  jNested = join {
    inputs = [
      jAB
      chC
    ];
    name = "jNested";
  };

  out = run {
    dag = compose [
      chA
      chB
      chC
      jAB
      jBA
      jCombine
      jNested
    ];
    inherit traversal;
  };
  vals = name: (out.at "p").${name}.values;
in
{
  flake.tests.law-join-determinism = {
    # concatenation in pinned input order [A B]
    test-join-order-AB = {
      expr = vals "jAB";
      expected = [
        "a1"
        "a2"
        "b1"
      ];
    };
    # deterministic across two evals
    test-join-deterministic = {
      expr = vals "jAB" == vals "jAB";
      expected = true;
    };
    # permuting inputs [B A] is a SEMANTIC change — different sequence
    test-join-permutation-differs = {
      expr = vals "jBA";
      expected = [
        "b1"
        "a1"
        "a2"
      ];
    };
    # join-with-combine left-folds the pinned sequence to one synthetic contribution (count = 3).
    # A scalar-reducing channel is read through its single contribution (the default list-concat
    # channel value does not apply to a scalar fold result).
    test-join-combine-fold = {
      expr = builtins.map (c: c.value) (out.at "p").jCount.contributions;
      expected = [ 3 ];
    };
    # nested join: [jAB C] ⇒ jAB's sequence then C
    test-nested-join = {
      expr = vals "jNested";
      expected = [
        "a1"
        "a2"
        "b1"
        "c1"
      ];
    };
  };
}
