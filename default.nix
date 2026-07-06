# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-pipe is a function of `prelude` (required — gen-prelude, the pure utility base) and
# `select` (required — gen-select, the selector algebra behind route/tee/consume predicates).
# `scope` is OPTIONAL: gen-pipe consumes only gen-scope's traversal-contract shape, and every
# operator works against a hand-built stub adapter, so the gen-scope value is not needed for
# the core algebra (it is wired for the integration path). The defaults fetch the flake-locked
# revs (content-addressed via narHash, so the plain-import path stays pure and in lockstep with
# the flake output; per the gen root-file convention).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ? name: builtins.fetchTree (lock.nodes.${lock.nodes.root.inputs.${name}}.locked),
  prelude ? import "${fetch "gen-prelude"}/lib",
  select ? import "${fetch "gen-select"}/lib",
  scope ? import "${fetch "gen-scope"}/lib" { inherit prelude; },
}:
import ./lib { inherit prelude select scope; }
