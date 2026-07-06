# The checked read (§2.7). `consume` walks the channel's post-dedup sequence at a position and, per
# contribution: applies `select`, enforces class discipline (tag = class → pass; tag = null → pass;
# else adapter path, else E2; a class-neutral read accepts only neutral contributions, else E2c),
# attaches the matched adapter + the channel's `type` check (composed into the deferred fn, applied
# immediately for resolved values), and returns either values (deferred resolved now via
# `resolveDeferred`, E11 if absent) or consumption records (the deferred-to-consumer seam, §4.8).
{
  prelude,
  errors,
  helpers,
  select,
}:
let
  inherit (prelude)
    filter
    map
    length
    head
    any
    ;
  inherit (helpers) entryEq;
  inherit (select) matchView;

  addHop =
    c: hop:
    c
    // {
      provenance = c.provenance // {
        hops = c.provenance.hops ++ [ hop ];
      };
    };

  # Duplicate (from,to) across the combined adapter list (channel-declared ++ consume-supplied) is
  # E2b — the consume-site list EXTENDS, it never shadows (§2.6.5).
  firstDupPair =
    ads:
    let
      step =
        acc: a:
        if any (q: entryEq q.from a.from && entryEq q.to a.to) acc.seen then
          acc // { dup = a; }
        else
          acc // { seen = acc.seen ++ [ a ]; };
    in
    (foldl' step { seen = [ ]; } ads);
  foldl' = prelude.foldl';
in
{
  consume =
    {
      outputs,
      at,
      channel,
      class ? null,
      adapters ? [ ],
      select ? null, # gen-select selector value or view->bool predicate
      mode ? "values",
    }:
    let
      # A derived channel VALUE carries no final name until `compose` assigns one (§2.3a); resolve it
      # from the dag by identity (id) so callers can pass the operator-returned channel value directly.
      name =
        if channel.name != null then
          channel.name
        else
          let
            chans = outputs.__dag.channels;
            cands = prelude.filter (nm: (chans.${nm}.id or nm) == channel.id) (prelude.attrNames chans);
          in
          if cands != [ ] then head cands else channel.id;
      out = outputs.at at;
      resolver = outputs.__resolveDeferred or null;
      seq = out.${name}.contributions;
      allAdapters = channel.class.adapters ++ adapters;
      dup = firstDupPair allAdapters;
      typeContract = channel.type;

      selected = if select == null then seq else filter (c: matchView select c) seq;

      # type check + adapter coercion, composed for deferred contributions (execute post-resolution
      # on either route), applied immediately for resolved ones (E9 lazy per value).
      applyChecks =
        c: adapter:
        let
          typeCheck =
            v:
            if typeContract == null || typeContract.check v then
              v
            else
              throw (
                errors.e9 {
                  channel = name;
                  description = typeContract.description or null;
                  producer = c.producer;
                }
              );
          adapt = v: if adapter == null then v else adapter.fn v c.provenance;
        in
        if c.deferred then
          c // { fn = env: typeCheck (adapt (c.fn env)); }
        else
          c // { value = typeCheck (adapt c.value); };

      checkContribution =
        c:
        let
          tag = c.class;
        in
        if class == null then
          # class-neutral read: only class-neutral contributions (E2c otherwise). A deferred
          # contribution always carries a tag (L9), so a neutral read never receives deferred content.
          if tag == null then
            applyChecks c null
          else
            throw (
              errors.e2c {
                channel = name;
                inherit tag;
                producer = c.producer;
              }
            )
        else if tag == null then
          applyChecks c null # class-neutral data flows freely
        else if entryEq tag class then
          applyChecks c null # same class
        else
          let
            matches = filter (a: entryEq a.from tag && entryEq a.to class) allAdapters;
          in
          if matches == [ ] then
            throw (
              errors.e2 {
                channel = name;
                consumingClass = class;
                inherit tag;
                producer = c.producer;
              }
            )
          else
            applyChecks (addHop c {
              op = "adapted";
              from = tag;
              to = class;
            }) (head matches)
            // {
              class = class;
            };

      processed = map checkContribution selected;

      resolveValueMode =
        c:
        if c.deferred then
          if resolver == null then
            throw (
              errors.e11 {
                channel = name;
                producer = c.producer;
              }
            )
          else
            resolver c # applies c.fn (checks composed) to the §2.6.4 environment
        else
          c.value;

      consumptionRecord = c: {
        __genPipeConsumption = true;
        contribution = c;
        inherit (c) class deferred;
        resolve = env: if c.deferred then c.fn env else c.value;
      };
    in
    assert (
      if dup ? dup then
        throw (
          errors.e2b {
            channel = name;
            inherit (dup.dup) from to;
          }
        )
      else
        true
    );
    if mode == "values" then map resolveValueMode processed else map consumptionRecord processed;
}
