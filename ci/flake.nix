{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-select.url = "github:sini/gen-select";
    gen-scope.url = "github:sini/gen-scope";
    gen-scope.inputs.gen-prelude.follows = "gen-prelude";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib`
    # the test modules use. nixpkgs enters ONLY here (a VALUE in ci/), never a `lib/` dep — the
    # library (../lib) is nixpkgs-lib-free (ci/tests/purity.nix enforces this).
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      gen-select,
      gen-scope,
      ...
    }:
    let
      genPipe = import ../lib {
        prelude = gen-prelude.lib;
        select = gen-select.lib;
        scope = gen-scope.lib;
      };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-pipe";
      testModules = ./tests;
      specialArgs = {
        inherit genPipe;
        genPrelude = gen-prelude.lib;
        genSelect = gen-select.lib;
        genScope = gen-scope.lib;
      };
    };
}
