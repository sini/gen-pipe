# Provenance & trace introspection (§4.5, §4.6, L8). Lineage/where-provenance-shaped (Cheney,
# Chiticariu & Tan 2009, "Provenance in Databases: Why, How, and Where") — each output value traces
# to its source contributions and the operator path. gen-pipe does NOT implement the semiring-
# annotated generality of Green–Karvounarakis–Tannen (2007); the survey is cited, not the semiring
# framework, to keep the claim honest.
#
# Bare scalar values carry no provenance (Nix cannot attach metadata to scalars); recovery goes
# through the paired contribution/consumption record.
{
  prelude,
  helpers,
  select,
}:
let
  inherit (prelude) filter concatMap;
  inherit (helpers) entryEq;
  inherit (select) matchView;
in
{
  # Recover the full structured chain from any contribution record OR consumption record (§4.8).
  provenanceOf =
    record:
    if record.__genPipeConsumption or false then
      record.contribution.provenance
    else if record.__genPipeContribution or false then
      record.provenance
    else
      throw "gen-pipe.provenanceOf: expects a contribution record or a consumption record";

  # The per-position, per-channel trace (§4.6): the full post-dedup sequence, every dedup drop, and
  # inbound-delivery order — the "never silent" law made inspectable.
  #
  # Passing a consuming `class` (with an optional `adapters` extension and `select`, mirroring
  # `consume`, §2.7) recomputes the trace's `adapted` records for that class: one record per
  # cross-class contribution the matching consume would coerce, in sequence order (§2.6.5). Every
  # adapter application therefore surfaces as a trace record, not only as a per-contribution
  # provenance hop — the "never silent" law made inspectable at the channel level too (L9). The bare
  # (class = null) trace is class-agnostic: adaptation is class-relative, so it carries no `adapted`
  # entries. Metadata-only throughout — forces no contribution value.
  traceOf =
    {
      outputs,
      at,
      channel,
      class ? null,
      adapters ? [ ],
      select ? null,
    }:
    let
      # Resolve a derived channel's compose-assigned final name by identity (§2.3a); a declared or
      # explicitly-named channel already carries it.
      name =
        if channel.name != null then
          channel.name
        else
          let
            chans = outputs.__dag.channels;
            cands = builtins.filter (nm: (chans.${nm}.id or nm) == channel.id) (builtins.attrNames chans);
          in
          if cands != [ ] then builtins.head cands else channel.id;
      out = outputs.at at;
      base = out.${name}.trace;
    in
    if class == null then
      base
    else
      let
        allAdapters = outputs.__dag.channels.${name}.class.adapters ++ adapters;
        seq = out.${name}.contributions;
        selected = if select == null then seq else filter (c: matchView select c) seq;
        # A cross-class contribution (tag ≠ consuming class, tag ≠ null) with a matching (from,to)
        # adapter is coerced by consume; record that application. Unmatched cross-class is E2 at
        # consume; the trace stays metadata-only and does not fire it.
        adapted = concatMap (
          c:
          let
            tag = c.class;
            matches = filter (a: entryEq a.from tag && entryEq a.to class) allAdapters;
          in
          if tag == null || entryEq tag class || matches == [ ] then
            [ ]
          else
            [
              {
                contribution = c.provenance.base;
                from = tag;
                to = class;
              }
            ]
        ) selected;
      in
      base // { inherit adapted; };
}
