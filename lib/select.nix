# gen-select adapter (§2.3, §2.7, §5). Selectors match against the read-only contribution VIEW.
# `select` may be either a gen-select selector value (`{ __sel = …; }`, matched via gen-select's
# `matches` over a single-node view context) or a plain predicate `view -> bool` (filter's `p` form).
#
# `sel.entity <entry>` / `sel.kind <kind>` are the roadmap §8 identity constructors. The pinned/
# published gen-select lacks them (it ships `sel.entityKind` keyed by a name string), so gen-pipe
# supplies them here as identity-law-honoring sugar over gen-select's `attrs` constructor, matched
# against the view projection below. `sel.<rest>` re-exports the upstream constructors so callers
# have one selector surface.  (Recorded as a deviation: pending gen-select §8, these live here.)
{
  prelude,
  select,
  helpers,
}:
let
  inherit (prelude) isFunction isAttrs;
  inherit (helpers) idOf kindOf;

  # The view a predicate/selector receives: the contribution record read-only, with `.value`
  # behaving per §2.6.3 (a poisoned E6 thunk while deferred — touching it throws).
  viewOf = c: {
    inherit (c)
      producer
      class
      deferred
      value
      provenance
      ;
    channel = c.channel.name or null;
    classInvariant = c.classInvariant;
  };

  # Flat data projection consumed by gen-select `attrs` / `star` / `when` selectors. Coordinate
  # selectors match `producer.scope` (each coord flattened by its kind key to the entry id_hash).
  dataProjection =
    c:
    {
      entity = idOf c.producer.entity;
      kind =
        let
          k = kindOf c.producer.entity;
        in
        if k == null then null else idOf k;
      class = if c.class == null then null else idOf c.class;
      deferred = c.deferred;
      channel = c.channel.name or null;
    }
    // (if c.producer.scope == null then { } else builtins.mapAttrs (_: v: idOf v) c.producer.scope);

  # A single-node accessor context: a contribution view has no graph neighbourhood, so children /
  # ancestors are empty and parent is null. gen-select's `attrs`/`star`/`when`/`not`/`and`/`any`
  # tags evaluate against `ctx.data`.
  viewContext = c: {
    data = _: dataProjection c;
    children = _: [ ];
    ancestors = _: [ ];
    parent = _: null;
  };

  matchView =
    sel: c:
    if sel == null then
      true
    else if isFunction sel then
      sel (viewOf c) # filter's predicate-over-view form
    else if isAttrs sel && sel ? __sel then
      select.matches sel "self" (viewContext c)
    else
      throw "gen-pipe: select must be a gen-select selector or a view->bool predicate";

  # gen-pipe's selector surface: upstream gen-select constructors + the identity constructors.
  sel = select // {
    entity = entry: select.attrs { entity = idOf entry; };
    kind = k: select.attrs { kind = idOf k; };
    all = select.star;
  };
in
{
  inherit
    viewOf
    matchView
    sel
    ;
}
