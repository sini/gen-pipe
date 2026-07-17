# Channel declaration (§2.1 / §4.1) and discipline validation (E10/E10b). A channel is declared once
# and instantiated per scope position at run time; its value at a position is the left fold of its
# pinned, deduped contribution sequence under the associative-only combine (L1).
{ prelude, errors }:
let
  # The known merge disciplines. `ordered-list` (the default) is the associative-only ordered fold;
  # `semilattice-set` is the idempotent set-union class (below). Anything else is unknown (E10b).
  knownMerges = [
    "ordered-list"
    "semilattice-set"
  ];

  # Discipline validation fires primarily here (channel construction) and is re-validated by compose
  # for hand-built records — same golden message at both firing points (§2.5 item 3). Both known
  # disciplines pass; an unknown one aborts E10b. (E10 — the semilattice-set RESERVED throw — is
  # retired now that the class is real; the slot is a live discipline, not a reserved sentinel.)
  validateMerge =
    name: merge:
    if builtins.elem merge knownMerges then
      merge
    else
      throw (
        errors.e10b {
          channel = name;
          inherit merge;
        }
      );

  # Default combine + init: the associative-only left fold whose default is ordered list
  # concatenation, so the default channel value is the ordered contribution list (§2.1). `init` is
  # the fold seed (§2.1 writes `foldl combine init …`); it is an argument-shape refinement of the API
  # sketch, unavoidable so an empty channel folds to `init` rather than erroring.
  defaultCombine = a: b: a ++ b;

  # THE SEMILATTICE-SET CLASS (§B5 rule 3, the HOAG disciplines laws ladder). An idempotent set-union
  # merge: duplicate contribution VALUES collapse (dedup by `==`), so re-contributing an already-present
  # value is a no-op. It satisfies the JOIN-SEMILATTICE laws — associativity, commutativity, idempotence
  # (ACI): Arntzenius & Krishnaswami's Datafun restricts a fixpoint's carrier to exactly such a
  # semilattice (idempotence is what makes the reachable-set iteration converge), and Shapiro et al.'s
  # CRDTs are the convergent-replicated instance of the same algebra. The fold never branches on `merge`;
  # the class is realized as CHANNEL-CONSTRUCTION DEFAULTS — a value-keyed first-occurrence dedup on top
  # of the ordered append. RESULT ORDER = FIRST-OCCURRENCE (pinned-order stable): the earliest occurrence
  # of each distinct value survives in place, a later duplicate drops. A caller may override dedup.
  semilatticeSetDedup = {
    key = view: view.value; # dedup by the contribution VALUE (`==` via the key's JSON serialization)
    keep = "first"; # first occurrence survives → the result set is pinned-order stable
  };
in
{
  inherit validateMerge defaultCombine;

  channel =
    {
      name,
      type ? null,
      merge ? "ordered-list",
      combine ? defaultCombine,
      init ? [ ],
      dedup ? null,
      class ? { },
    }:
    let
      validMerge = validateMerge name merge;
      # the semilattice-set class defaults dedup to value-keyed first-occurrence (idempotent set-union),
      # UNLESS the caller declared an explicit dedup policy (an override always wins).
      effectiveDedup =
        if validMerge == "semilattice-set" && dedup == null then semilatticeSetDedup else dedup;
    in
    {
      __genPipeChannel = true;
      __derived = false;
      id = name; # a declared channel's identity IS its name
      inherit
        name
        type
        combine
        init
        ;
      dedup = effectiveDedup;
      merge = validMerge;
      class = {
        expect = class.expect or null;
        adapters = class.adapters or [ ];
      };
    };
}
