# Contribution construction + validation (§2.2, §2.6.2, §4.2). `contribute` is pure record
# construction: it tags the class (T1–T4), derives the static config-dependence flag (L13),
# poisons the deferred value (E6), and seeds provenance. den-hoag compiles an aspect's channel emit
# to `contribute` at each position where the aspect resolves (dual inclusion = two contributions,
# one per producing position — §2.6.1).
{
  prelude,
  errors,
  helpers,
  deferred,
}:
let
  inherit (prelude) length head elemAt;
  inherit (helpers) configArgsOf entryEq;
  inherit (deferred) isDeferred poison;

  # Tagging rules T1–T4 (§2.6.2), ordered. `classes` is the list of class registry entries bound at
  # the producing position (traversal.classesOf position). den-hoag holds it and passes it through
  # `producer.classes`; it is what T2/T4/E7 need and is the natural extension of the producer
  # coordinate bundle (an argument-shape refinement of the §4.2 producer shape).
  resolveTag =
    {
      channel,
      producer,
      explicit,
      classes,
      isDef,
    }:
    if explicit != null then
      # T1 — explicit tag wins; must be bound at the position (E7) when the position's classes known.
      if classes == null || builtins.any (c: entryEq c explicit) classes then
        explicit
      else
        throw (
          errors.e7 {
            channel = channel.name;
            tag = explicit;
            inherit classes producer;
          }
        )
    else if !isDef then
      # T3 — class-neutral: plain data needs no class, no resolution environment is ever constructed.
      null
    else if classes != null && length classes == 1 then
      # T2 — the producing position binds exactly one class → that class is the tag.
      head classes
    else
      # T4 — deferred, no explicit tag, 0 or ≥2 classes (or unknown) → ambiguous, definition-time.
      throw (
        errors.e1 {
          channel = channel.name;
          inherit producer;
          classes = if classes == null then [ ] else classes;
        }
      );
in
{
  inherit resolveTag;

  contribute =
    {
      channel,
      value,
      producer,
      class ? null,
    }:
    let
      isDef = isDeferred value;
      classes = producer.classes or null;
      prod = {
        entity = producer.entity;
        scope = producer.scope or null;
        aspect = producer.aspect or null;
      };

      # E8 — a bare function demanding config-like args, passed without the deferred wrapper. den v1
      # sniffed functionArgs to CLASSIFY thunks; gen-pipe makes deferral declared and keeps the sniff
      # only as a lint that rejects the undeclared case, so a non-deferred contribution provably
      # carries no config dependence (the soundness of classInvariant = true, L13).
      demanded = if isDef then [ ] else configArgsOf value;

      tag = resolveTag {
        inherit channel producer isDef;
        explicit = class;
        inherit classes;
      };

      base = {
        producer = prod;
        rendered = null; # display, filled by run/consume via traversal.render
      };
    in
    if demanded != [ ] then
      throw (
        errors.e8 {
          channel = channel.name;
          producer = prod;
          inherit demanded;
        }
      )
    else
      {
        __genPipeContribution = true;
        channel = channel;
        deferred = isDef;
        # L13 arg-shape derivation: deferred ⇒ per-member (false); non-deferred ⇒ class-invariant
        # candidate (true), sound by E8. Derived, never an input to `contribute`.
        classInvariant = !isDef;
        class = tag;
        fn = if isDef then value.fn else null;
        # The args the deferred fn demands (functionArgs of the ORIGINAL fn). A resolver builds the
        # §2.6.4 environment and filters it to exactly these (map/adapter/type composition operate on
        # the resolved VALUE, so they never change the arg demand). null for non-deferred.
        argDemand = if isDef then builtins.functionArgs value.fn else null;
        value =
          if isDef then
            poison {
              channel = channel.name;
              producer = prod;
            }
          else
            value;
        producer = prod;
        provenance = {
          inherit base;
          hops = [ ];
        };
      };
}
