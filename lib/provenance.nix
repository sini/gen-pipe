# Provenance & trace introspection (§4.5, §4.6, L8). Lineage/where-provenance-shaped (Cheney,
# Chiticariu & Tan 2009, "Provenance in Databases: Why, How, and Where") — each output value traces
# to its source contributions and the operator path. gen-pipe does NOT implement the semiring-
# annotated generality of Green–Karvounarakis–Tannen (2007); the survey is cited, not the semiring
# framework, to keep the claim honest.
#
# Bare scalar values carry no provenance (Nix cannot attach metadata to scalars); recovery goes
# through the paired contribution/consumption record.
{ prelude }:
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
  traceOf =
    {
      outputs,
      at,
      channel,
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
    in
    (outputs.at at).${name}.trace;
}
