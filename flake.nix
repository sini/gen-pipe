{
  description = "gen-pipe — scoped channels + dataflow algebra (map/filter/fold/scan/route/join/tee) with B5 determinism, provenance, dedup, and class-aware contributions";

  # Class layering: gen-prelude → gen-pipe (Class B — L1-only deps, nothing upward,
  # nixpkgs-lib-free; ci/tests/purity.nix enforces this). gen-pipe consumes three L1 libs
  # as flake inputs:
  #   - gen-prelude : foundational combinators (builtins re-exports + vendored toposort).
  #   - gen-select  : routing / consumption predicates (route.select, tee.outputs[].select,
  #                   consume.select). gen-pipe ships only a small view-adapter over `matches`
  #                   (projecting the __identity/__coords contract); the identity/kind/coord
  #                   constructors are upstream now (roadmap §8) and re-exported verbatim as `sel`.
  #   - gen-scope   : the TRAVERSAL CONTRACT ONLY — gen-pipe consumes an adapter shaped after
  #                   gen-scope's collectionAttr pin (self → imports → parent, imports in
  #                   declaration order); it never constructs scope graphs. The dependency is
  #                   the contract surface, so the algebra stays testable against stub adapters.
  # gen-schema is NOT a dependency: registry entries are opaque identity-bearing values to
  # gen-pipe (it duck-types `id_hash` for dedup keys), so the identity law is honored without
  # a lib edge.
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-select.url = "github:sini/gen-select";
    gen-scope.url = "github:sini/gen-scope";
    gen-scope.inputs.gen-prelude.follows = "gen-prelude";
  };

  outputs =
    {
      gen-prelude,
      gen-select,
      gen-scope,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        select = gen-select.lib;
        # gen-scope enters only as the traversal-contract surface; the library takes it as an
        # optional dep (all core operators work against a stub adapter), so it is not required.
        scope = gen-scope.lib;
      };
    };
}
