# Shared pure helpers for gen-pipe. Identity-law plumbing (entries are opaque id_hash-bearing
# values — duck-typed, never a gen-schema lib edge), display rendering, and the config-argument
# arg-shape probe that drives the classInvariant partition (§2.6.7 / L13).
{ prelude }:
let
  inherit (prelude)
    isAttrs
    isFunction
    functionArgs
    attrNames
    filter
    elem
    concatStringsSep
    mapAttrsToList
    ;

  # The config-like argument names an emit may demand. A non-deferred contribution whose
  # underlying function demands any of these is E8 (undeclared deferral); the same probe drives
  # `map`'s taint (a config-reading map fn defers its output). "config"/"osConfig" are the class +
  # parent-config arguments of the den class model (nixos owns `config`; home-manager reaches its
  # owner via `osConfig`) — kept as a small fixed set here (den-hoag supplies the real parentArg
  # names through the same probe when it compiles quirks).
  configArgs = [
    "config"
    "osConfig"
  ];

  # Opaque identity read: registry entries carry a gen-schema `id_hash`; gen-pipe compares entries
  # by it without depending on gen-schema (§5). Falls back to a display name, then a structural key.
  idOf =
    e:
    if e == null then
      null
    else if isAttrs e then
      (e.id_hash or e.name or (builtins.toJSON e))
    else
      toString e;

  kindOf = e: if isAttrs e then (e.kind or e.__kind or e.kindName or null) else null;

  # Two entries are the same identity iff their id_hash (duck-typed) matches.
  entryEq = a: b: idOf a == idOf b;

  # Display name of a single entry — the only place a string is authoritative is a rendered message.
  renderEntry =
    e:
    if e == null then
      "<none>"
    else if isAttrs e then
      (e.name or e.displayName or e.id_hash or (builtins.toJSON e))
    else
      toString e;

  # Fallback structured-coordinate rendering ("host=axon-01, user=sini"). `run`/`consume` prefer the
  # caller's `traversal.render` (which produces "sini@axon-01"); errors that fire at `contribute`
  # (before any traversal) use this built-in form. Both satisfy the "names the rendered scope" gate.
  renderCoords =
    coords:
    if coords == null then
      "<no-scope>"
    else if isAttrs coords then
      concatStringsSep ", " (mapAttrsToList (k: v: "${k}=${renderEntry v}") coords)
    else
      toString coords;

  # Arg-shape probe: the config-like arguments a function demands (empty for a plain `x: …` lambda,
  # whose functionArgs is `{ }`). Drives E8 and the classInvariant taint.
  configArgsOf =
    f: if isFunction f then filter (a: elem a configArgs) (attrNames (functionArgs f)) else [ ];

  # Dedup identity key (L7): registry-entry identity + producing scope coordinates. Structured, not
  # a "kind:name" string — the string is an internal comparable key only.
  identityKey =
    producer:
    builtins.toJSON {
      entity = idOf producer.entity;
      scope = if producer.scope == null then null else builtins.mapAttrs (_: idOf) producer.scope;
    };
in
{
  inherit
    configArgs
    idOf
    kindOf
    entryEq
    renderEntry
    renderCoords
    configArgsOf
    identityKey
    ;
}
