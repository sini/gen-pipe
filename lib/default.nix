# gen-pipe public API — scoped channels + dataflow algebra (declaration / write-side / operators /
# composition / evaluation / consumption / introspection). Content-agnostic: gen-pipe reads the
# scope graph through a traversal adapter and produces plain data; no output feeds graph structure
# (B2 two-stratum, van Antwerpen et al. 2016 Statix via HOAG r2 §B2, L5).
#
# Class layering (§5): consumes gen-prelude (combinators) + gen-select (routing/consumption
# predicates). `scope` is the gen-scope traversal-contract surface — accepted for API symmetry and
# the integration path; the algebra itself runs against any conforming (incl. hand-built stub)
# adapter, so it is optional. nixpkgs-lib-free; gen-schema is NOT a dependency (registry entries are
# opaque id_hash-bearing values, duck-typed).
{
  prelude,
  select,
  scope ? null,
}:
let
  helpers = import ./helpers.nix { inherit prelude; };
  errors = import ./errors.nix { inherit prelude helpers; };
  deferred = import ./deferred.nix { inherit prelude errors; };
  channel = import ./channel.nix { inherit prelude errors; };
  contribute = import ./contribute.nix {
    inherit
      prelude
      errors
      helpers
      deferred
      ;
  };
  selectAdapter = import ./select.nix { inherit prelude select helpers; };
  operators = import ./operators.nix { inherit prelude channel; };
  compose = import ./compose.nix {
    inherit
      prelude
      errors
      helpers
      channel
      ;
  };
  evaluate = import ./evaluate.nix {
    inherit
      prelude
      errors
      helpers
      deferred
      ;
    select = selectAdapter;
  };
  consumeMod = import ./consume.nix {
    inherit prelude errors helpers;
    select = selectAdapter;
  };
  provenance = import ./provenance.nix { inherit prelude; };
in
{
  # ── declaration ──
  inherit (channel) channel;
  # ── write side ──
  inherit (contribute) contribute;
  inherit (deferred) deferred;
  # ── operators ──
  inherit (operators)
    map
    filter
    fold
    scan
    route
    join
    tee
    ;
  # ── assembly ──
  inherit (compose) compose;
  inherit (evaluate) run;
  inherit (consumeMod) consume;
  # ── introspection ──
  inherit (provenance) provenanceOf traceOf;
  # gen-select selector surface + the roadmap §8 identity constructors (sel.entity/sel.kind).
  inherit (selectAdapter) sel;
}
