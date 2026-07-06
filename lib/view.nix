# Contribution-view adapter (§2.3, §2.7, §5). Bridges a gen-pipe contribution into gen-select's
# single-node matcher context. A `select` argument is either a gen-select selector value
# (`{ __sel = …; }`, matched via gen-select's `matches` over the projection below) or a plain
# predicate `view -> bool` (filter's `p` form).
#
# The projection follows gen-select's adapter contract: identity/kind selectors read the reserved
# `__identity` record, coordinate selectors read `__coords` (the shape adapters.scope / adapters.registry
# / adapters.product produce). So upstream `sel.entity` / `sel.kind` / `sel.adapters.product.coord`
# match a contribution directly — gen-pipe supplies no selector constructors of its own (they live in
# gen-select, roadmap §8 landed @f3c047e).
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

  # Flat data projection the selector context matches against. gen-select's identity/kind selectors
  # read the reserved `__identity` record (id_hash + kind name), coord selectors read `__coords` (the
  # producing scope's coordinate tuple — raw registry entries, each id_hash-bearing); `attrs`/`when`
  # selectors read the plain fields. `__identity` is composed last so it is always present (record or
  # null) and never shadowed. `__identity.kind` is the producing entity's kind name; a kind-blind entity
  # projects `kind = null`, so `sel.kind` throws loud rather than silently never matching (the A1
  # discipline). A null producer entity projects `__identity = null` (a well-formed "not entity-backed"
  # node — matches nothing without throwing).
  dataProjection = c: {
    class = if c.class == null then null else idOf c.class;
    deferred = c.deferred;
    channel = c.channel.name or null;
    __coords = if c.producer.scope == null then { } else c.producer.scope;
    __identity =
      let
        e = c.producer.entity;
      in
      if e == null then
        null
      else
        {
          id_hash = idOf e;
          kind = kindOf e;
          entry = e;
        };
  };

  # A single-node accessor context: a contribution view has no graph neighbourhood, so children /
  # ancestors are empty and parent is null. gen-select's tags evaluate against `ctx.data`.
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
in
{
  inherit
    viewOf
    matchView
    ;
}
