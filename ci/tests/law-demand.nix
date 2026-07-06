# law-demand (L6). Unconsumed channels never evaluate: for every position/channel pair not
# transitively demanded, no contribution value, deferral, or combine of that pair is forced. Forcing
# (p, ch) forces only ch's DAG ancestor cone over the positions visible from p under the pin.
{
  genPipe,
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

  x = channel { name = "X"; };
  y = channel { name = "Y"; };

  # X carries a contribution whose VALUE throws when forced; Y is independent and well-behaved.
  boom = contribute {
    channel = x;
    value = throw "gen-pipe-test: X forced";
    producer = {
      entity = host "h1";
      scope.host = host "h1";
      aspect = null;
    };
  };
  yc = contribute {
    channel = y;
    value = [ "y" ];
    producer = {
      entity = host "h2";
      scope.host = host "h2";
      aspect = null;
    };
  };

  # position "p" reaches the writer of X; position "q" does not (its pin is empty).
  traversal = f.mkTraversal {
    table = {
      p = {
        X = [ boom ];
        Y = [ yc ];
      };
      q = {
        X = [ ];
        Y = [ ];
      };
    };
  };
  out = run {
    dag = compose [
      x
      y
    ];
    inherit traversal;
  };
  tri = builtins.tryEval;
in
{
  flake.tests.law-demand = {
    # consuming sibling Y succeeds even though X's value would throw — X is never forced.
    test-sibling-independent = {
      expr = (out.at "p").Y.values;
      expected = [ "y" ];
    };
    # forcing X's value does throw (proving the throw is real, and that Y avoided it).
    test-x-forces-throw = {
      expr = (tri (out.at "p").X.values).success;
      expected = false;
    };
    # consuming X at a position whose pin doesn't reach the writer succeeds (empty).
    test-x-unreached-position = {
      expr = (out.at "q").X.values;
      expected = [ ];
    };
    # X's metadata (contribution count) is available without forcing its value.
    test-x-metadata-no-force = {
      expr = builtins.length (out.at "p").X.contributions;
      expected = 1;
    };
  };
}
