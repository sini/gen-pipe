# Pinned error-message content (§2.8). The exact prose may evolve; the NAMED content is contract
# (golden tests assert each required field is present). Identities render via helpers.renderEntry /
# renderCoords (or the caller's traversal.render where one is in scope) — messages are the only
# place strings are authoritative.
{ prelude, helpers }:
let
  inherit (helpers) renderEntry renderCoords;
  inherit (prelude) concatStringsSep map;

  classList = classes: "[" + concatStringsSep ", " (map renderEntry classes) + "]";

  prod =
    producer:
    "aspect '${renderEntry (producer.aspect or null)}' entity '${renderEntry producer.entity}' at '${
      renderCoords (producer.scope or null)
    }'";
in
rec {
  # E1 — ambiguous producing class (deferred, no explicit tag, 0 or ≥2 classes).
  e1 =
    {
      channel,
      producer,
      classes,
    }:
    "gen-pipe[E1]: contribution to channel '${channel}' from ${prod producer} is deferred "
    + "(demands config) but its producing scope binds classes ${classList classes}; tag it "
    + "explicitly (class = <class entry>) or make it class-neutral (drop the deferred wrapper).";

  # E2 — cross-class consumption without adapter.
  e2 =
    {
      channel,
      consumingClass,
      tag,
      producer,
    }:
    "gen-pipe[E2]: channel '${channel}' consumed at class '${renderEntry consumingClass}' but a "
    + "contribution is tagged class '${renderEntry tag}' (${prod producer}); declare "
    + "class.adapters = [{ from; to; fn; }] on the channel or consume at the producing class.";

  # E2b — duplicate adapter (from, to) pair.
  e2b =
    {
      channel,
      from,
      to,
    }:
    "gen-pipe[E2b]: channel '${channel}' declares more than one adapter for the class pair "
    + "(${renderEntry from} -> ${renderEntry to}).";

  # E2c — class-tagged contribution in a class-neutral read.
  e2c =
    {
      channel,
      tag,
      producer,
    }:
    "gen-pipe[E2c]: class-neutral read of channel '${channel}' received a contribution tagged "
    + "class '${renderEntry tag}' (${prod producer}); the read declared no class.";

  # E3 — dataflow cycle at compose.
  e3 =
    { cycle, ops }:
    "gen-pipe[E3]: dataflow cycle in channels ${concatStringsSep " -> " cycle} "
    + "(via operators ${concatStringsSep ", " ops}).";

  # E4a — unknown channel reference.
  e4a =
    { op, name }:
    "gen-pipe[E4a]: operator '${op}' references channel '${name}', which is not in the "
    + "declaration set.";

  # E4b — duplicate channel name.
  e4b = { name }: "gen-pipe[E4b]: duplicate channel name '${name}' in the composed DAG.";

  # E5 — dedup conflict under keep = "error".
  e5 =
    {
      channel,
      key,
      kept,
      dropped,
    }:
    "gen-pipe[E5]: dedup conflict on channel '${channel}' for identity key '${key}': "
    + "kept ${prod kept}, dropped ${prod dropped}.";

  # E6 — value access on an unresolved deferred contribution.
  e6 =
    {
      channel,
      op,
      producer,
    }:
    "gen-pipe[E6]: channel '${channel}': operator '${op}' forced .value of an unresolved deferred "
    + "contribution (${prod producer}); deferred contributions resolve at the producing class+scope, "
    + "value-demanding operators require resolved values.";

  # E7 — explicit tag not bound at the producing position.
  e7 =
    {
      channel,
      tag,
      classes,
      producer,
    }:
    "gen-pipe[E7]: explicit class '${renderEntry tag}' on a contribution to channel '${channel}' is "
    + "not bound at the producing position (classes ${classList classes}) for ${prod producer}.";

  # E8 — undeclared deferral (bare config-demanding function).
  e8 =
    {
      channel,
      producer,
      demanded,
    }:
    "gen-pipe[E8]: contribution to channel '${channel}' from ${prod producer} is a bare function "
    + "demanding config-like args [${concatStringsSep ", " demanded}] without the deferred wrapper; "
    + "wrap it in genPipe.deferred.";

  # E9 — type-contract violation (attached at consumption, executes post-resolution).
  e9 =
    {
      channel,
      description,
      producer,
    }:
    "gen-pipe[E9]: channel '${channel}' value fails its type contract "
    + "(${if description == null then "<no description>" else description}) for ${prod producer}.";

  # E10 / E10b — reserved / unknown discipline.
  e10 =
    { channel, merge }:
    "gen-pipe[E10]: channel '${channel}' declares reserved discipline '${merge}'; semilattice-set is "
    + "reserved and rejected until a real idempotent-set consumer exists (HOAG r2 §B5 rule 3).";
  e10b =
    { channel, merge }:
    "gen-pipe[E10b]: channel '${channel}' declares unknown discipline '${merge}'.";

  # E11 — deferred contribution in a value-mode read with no resolver.
  e11 =
    { channel, producer }:
    "gen-pipe[E11]: value-mode read of channel '${channel}' hit a deferred contribution "
    + "(${prod producer}) with no traversal.resolveDeferred; supply resolveDeferred (resolve-at-source) "
    + "or read with mode = \"records\" and resolve in the consuming class binding.";
}
