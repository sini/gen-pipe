# gen-pipe — API Reference

Scoped channels + dataflow algebra. All public entry points pass and receive **values** (channel
values, contribution records, registry entries) — never `"kind:name"` strings (identity law).
Registry entries are opaque `id_hash`-bearing values; gen-pipe duck-types `id_hash` for dedup keys
and compares entries by it, so gen-schema is **not** a dependency.

- [Declaration](#declaration)
- [Write side](#write-side)
- [Operators](#operators)
- [Composition & evaluation](#composition--evaluation)
- [Consumption](#consumption)
- [Introspection](#introspection)
- [Selectors](#selectors)
- [Class semantics](#class-semantics)
- [Config-dependence flag](#config-dependence-flag)
- [Data shapes](#data-shapes)
- [Failure modes](#failure-modes)
- [Laws](#laws)

______________________________________________________________________

## Declaration

### `channel`

```nix
channel = {
  name,                        # display + internal key (unique within a dag)
  type ? null,                 # { check = v: bool; description ? str; } — duck-typed, gen-types plugs in
  merge ? "ordered-list",      # discipline; "semilattice-set" reserved + rejected (E10)
  combine ? (a: b: a ++ b),    # associative-only left fold
  init ? [ ],                  # fold seed (value = foldl combine init seqValues)
  dedup ? null,                # dedup policy record or null = off
  class ? { },                 # { expect ? <class entry>|null; adapters ? [ <adapter> ]; }
}: <channel>;
```

Determinism rests on the traversal pin, not the combine's algebra. The combine must be associative;
it need **not** be commutative or idempotent — swapping a commutative/idempotent combine into an
ordered-list channel is a correctness regression (it reorders and dedups), not an optimization.

`merge = "semilattice-set"` is **reserved and rejected** (E10) until a real idempotent-set consumer
exists. Unknown disciplines are E10b.

______________________________________________________________________

## Write side

### `contribute`

```nix
contribute = {
  channel,                     # <channel> value
  value,                       # plain value, or genPipe.deferred fn
  producer,                    # { entity; scope; aspect ? null; classes ? null; }
  class ? null,                # explicit class entry (tagging rule T1)
}: <contribution>;
```

`producer.entity` and `producer.aspect` are registry entries; `producer.scope` is an attrset of
registry entries (structured scope coordinates). `producer.classes` is the list of class registry
entries bound at the producing position (`traversal.classesOf position`) — den-hoag holds it and
passes it; it is what tagging rules T2/T4 and E7 need.

Pure record construction + validation, so den-hoag (and tests) build contributions anywhere. Never
collects contributions itself.

### `deferred`

```nix
deferred = fn: <deferredValue>;
```

Marks a value as config-demanding. `fn` is a function of an attrset whose `functionArgs` may demand
`config`, the producing class's registered parent-config argument (e.g. `osConfig`), scope-context
bindings, and `lib`. Until resolution the contribution's `value` field is a poisoned thunk throwing
E6. `map` composes into `fn`. A **bare** function demanding config-like args passed *without* the
wrapper is E8.

______________________________________________________________________

## Operators

Operators are edges of the dataflow DAG; each application declares a new channel (or delivery edge)
and never mutates its input — all operators are non-destructive reads (a channel's value never
depends on who else reads it).

| Operator | Signature | Semantics |
|---|---|---|
| `map` | `f: <channel>: <channel>` | Per-contribution value transform; provenance hop appended; class tag/producer/identity preserved. Composes into a deferred value's thunk. |
| `filter` | `p: <channel>: <channel>` | Keeps contributions where `p view` is true (metadata-safe; touching `.value` of an unresolved deferred contribution is E6). Preserves relative order. |
| `fold` | `{ f, init, ... }: <channel>: <channel>` | Left fold over the pinned sequence's values ⇒ one synthetic contribution (producer = folding position, class = null). Value-demanding (E6 on unresolved deferred input). |
| `scan` | `{ f, init, ... }: <channel>: <channel>` | Emits every intermediate accumulator in input order — exactly one output per input; `init` never emitted (empty input ⇒ empty output). |
| `route` | `{ from, select, to }: <op>` | Selective copy: `from` contributions matching `select` are *also* delivered to `to`, in `from`-order, provenance hop appended. `from` unchanged. |
| `join` | `{ inputs, combine ?, ... }: <channel>` | Fan-in across channels: output = concatenation of each input's B5-ordered sequence, inputs in list order. With `combine = { f; init; }`, left-folds to one synthetic contribution. |
| `tee` | `{ from, outputs }: <op>` | Side outputs: each `{ select ? null, to }` receives the source-order subsequence of `from` matching `select`. `route` is the unary special case. |

Every deriving operator also accepts a **record form** carrying identity/attributes:
`map { f, name ?, type ?, dedup ?, class ? }` (likewise `filter { p, ... }`, `fold/scan { f, init, ... }`, `join { inputs, combine ?, ... }`).

### Derived-channel identity & attributes

- **Identity.** The record form's `name` names the derived channel explicitly. Without one, `compose`
  assigns `"<inputName>.<op>.<declIndex>"` (`"join.<declIndex>"` for multi-input `join`), where
  `declIndex` is the channel's index in the `decls` list.
- **Attributes reset to declaration defaults — never inherited.** A derived channel gets
  `merge = "ordered-list"`, list-concat `combine`, `dedup = null`, `type = null`, `class = { }`.
  Consequence: dedup and adapters never apply twice silently. Re-declare a contract via the record
  form.
- Distinct derivations over the same input+op without an explicit name share a base id — give them
  explicit names (see [Deviations](#deviations)).

______________________________________________________________________

## Composition & evaluation

### `compose`

```nix
compose = decls: <dag>;
```

Takes the declaration list (channels + operators, any order — they carry their own edges) and returns
a validated DAG value. All validation is definition-time and forces DAG **structure** only, never
contribution values:

1. **Acyclicity** (E3) — naming the channel cycle and the operators forming it.
1. **Reference closure** (E4a) + unique channel names (E4b) — derived names assigned + checked here.
1. **Discipline validity** (E10/E10b) + dedup policy well-formedness.
1. **Static class coverage** (E2) — a delivery edge from a class-tagged channel into a channel whose
   `class.expect` differs requires a declared adapter (when statically decidable).

### `run`

```nix
run = { dag, traversal }: <outputs>;

outputs.at <position> = { <channelName> = { values; contributions; trace; classInvariant; }; };
```

`<channelName>` ranges over declared **and** derived names. `outputs` is **lazy** in both position and
channel: consuming `(p, ch)` forces exactly `ch`'s ancestor cone at the positions the pin makes
visible from `p` — an unconsumed channel's contributions are never evaluated. Raw `.values` /
`.contributions` are **unchecked** (deferred entries there are poisoned E6 thunks); go through
`consume` for the checked read.

### The traversal adapter

The caller's (den-hoag's) projection of the scope graph, conforming to gen-scope's collection
contract:

```nix
traversal = {
  order = position: [ <position> ];        # visibility sequence: self → imports (decl order) → parent
  contributionsAt = position: channelName: [ <contribution> ];   # declared channels only
  classesOf = position: [ <class entry> ]; # class bindings of a position (usually 0 or 1)
  render = coords: str;                     # display rendering of structured coordinates
  resolveDeferred ? contribution: value;    # OPTIONAL: eager cross-boundary resolution (§value mode)
};
```

______________________________________________________________________

## Consumption

### `consume`

```nix
consume = {
  outputs, at, channel,
  class ? null,          # consuming class REGISTRY ENTRY; null = class-neutral read
  adapters ? [ ],        # consumption-site adapter EXTENSION (never shadows; duplicate pair = E2b)
  select ? null,         # gen-select selector value OR view->bool predicate
  mode ? "values",       # "values" | "records"
}: [ value ] | [ <consumptionRecord> ];
```

The checked read. Per contribution of the channel's post-dedup sequence at `at`, in order:

1. **Select** — applied to the contribution view (metadata-safe).
1. **Class discipline** — tag = consuming class → pass; tag = null (neutral) → pass; otherwise the
   adapter path applies, else E2. A `class = null` read accepts **only** class-neutral contributions
   (E2c otherwise). Since a deferred contribution always carries a tag, a neutral read never receives
   deferred content.
1. **Checks attached** — the matched adapter and the channel's `type` check compose into the deferred
   fn (execute post-resolution) or apply immediately for resolved values. Type failure = E9.
1. **Return** by `mode`:
   - `"values"` (default): `[ value ]`. Deferred contributions are resolved **now** via
     `traversal.resolveDeferred` (resolve-at-source). Missing resolver + deferred present = E11.
   - `"records"`: `[ <consumptionRecord> ]` — the deferred-to-consumer seam. Each record carries the
     checked contribution + a `resolve = env: value` entry point applying the composed fn; a resolved
     contribution's `resolve` ignores its argument.

______________________________________________________________________

## Introspection

```nix
provenanceOf = record: <chain>;              # from a contribution OR consumption record (§4.5)
traceOf      = { outputs, at, channel }: <trace>;   # the per-position, per-channel trace (§4.6)
```

`provenanceOf` recovers the full structured chain (base + hops). Bare scalar values carry no
provenance — recovery goes through the paired record. The trace is the "never silent" law made
inspectable: every dedup drop and delivery is a record.

______________________________________________________________________

## Selectors

`genPipe.sel` re-exports the gen-select constructors plus the identity constructors:

```nix
sel.entity <registry-entry>   # match a specific entity by identity (id_hash)
sel.kind   <schema-kind>      # match all entities of a kind
sel.all                       # = gen-select's star (catch-all)
```

A `select` argument is either a gen-select selector value (matched against the contribution view via a
single-node accessor context) or a plain `view -> bool` predicate. Coordinate selectors match
`producer.scope`; `sel.entity`/`sel.kind` match `producer.entity`.

> The pinned/published gen-select lacks `sel.entity`/`sel.kind` (roadmap §8); gen-pipe supplies them
> locally, honoring the identity law, pending the gen-select extension. See [Deviations](#deviations).

______________________________________________________________________

## Class semantics

**Tagging rules (ordered):**

- **T1 — explicit tag wins.** `class = <entry>` sets the tag; must be bound at the position (else E7).
- **T2 — unique position class.** No explicit tag, producing position binds exactly one class → that
  class. (user position → home-manager, host position → nixos.)
- **T3 — class-neutral.** No explicit tag, value is plain data → `class = null`. Consumable anywhere,
  no adapter, no resolution environment ever constructed.
- **T4 — ambiguity is an error.** No explicit tag, value is deferred, position binds 0 or ≥2 classes →
  **E1**.

**Resolution environment.** A deferred contribution tagged `k`, produced at coordinates `S`, resolves
by applying `fn` to `{ config = <class k's config at S>; ${parentArg} = <owner config at S>; } ∪ <scope context filtered to fn's demanded args> ∪ { inherit lib; }`. Whichever resolution route runs
(resolve-at-source `mode = "values"`, or deferred-to-consumer `mode = "records"`), `fn` receives the
same environment. The contribution exposes `argDemand` (the `functionArgs` of the original fn) so a
resolver can filter the environment to exactly the demanded args.

**Adapters** (cross-class coercion):

```nix
{ from = <class entry>; to = <class entry>; fn = value: provenance: <value'>; }
```

`fn` receives the **resolved** value + the provenance chain (never a thunk — for a deferred
contribution the coercion composes into the deferred fn). At the consumption boundary a contribution
whose tag ≠ the consuming class is matched by `(from, to)` identity: exactly one match → re-tagged,
`adapted` hop appended, coercion applied; zero → E2; duplicate pair → E2b. Class-neutral
contributions bypass adaptation.

______________________________________________________________________

## Config-dependence flag

Every contribution and derived output carries `classInvariant : bool` — a **static** property derived
from arg-shape, composed through operators at composition time, never a runtime discovery.

- A **deferred** contribution → `false` (per-member by construction).
- A **non-deferred** contribution → `true` (config-independent; E8 makes this sound).

`classInvariant = true` marks a **candidate** for a class's shared core (config-independent). It does
**not** assert byte-identity across members — gen-pipe guarantees only the sound necessary direction
(`false` ⟹ never shared); byte authority is gen-class's `gateCore`. Taint propagation:

| Operator | `classInvariant` of output |
|---|---|
| `map f` | preserved when `f` is config-free; config-reading `f` ⇒ `false`. |
| `filter p` | preserved (metadata predicate). |
| `fold`/`scan` | `(all inputs invariant) && configFree(f)`. |
| `join` | pass-through; join-with-combine follows the fold rule. |
| `route`/`tee` | deliveries preserve each contribution's flag. |

The class-invariant set of a channel is therefore computable at `compose` time **without forcing any
contribution value**.

______________________________________________________________________

## Data shapes

**Contribution** (`__genPipeContribution`):

```nix
{
  channel; value;                       # value = resolved value, or poisoned E6 thunk while deferred
  deferred = false | true;
  classInvariant = true | false;        # static config-dependence partition
  fn = null | <deferred fn>;            # internal; composed by map/adapters/type checks
  argDemand = null | <functionArgs>;    # args the deferred fn demands (for env filtering)
  class = null | <class entry>;         # tag per T1–T4
  producer = { entity; scope; aspect; };
  provenance = { base = { producer; rendered; }; hops = [ … ]; };
}
```

**Dedup policy**: `{ key ? "identity"; keep ? "first"; }` — `"identity"` key =
`(producer.entity.id_hash, producer.scope coords)`; `keep` ∈ `"first" | "last" | "error"` (E5).

**Provenance hop** (one of): `{ op = "map"|"filter"; channel; }`, `{ op = "route"|"tee"; from; to; }`,
`{ op = "join"; to; inputIndex; }`, `{ op = "fold"|"scan"; channel; inputs; }`,
`{ op = "adapted"; from; to; }`.

**Channel trace** (`traceOf`): `{ channel; position; sequence; deduped; adapted; routedIn; }` — every
dedup drop and inbound delivery recorded.

**Consumption record** (`__genPipeConsumption`): `{ contribution; class; deferred; resolve = env: value; }`.

______________________________________________________________________

## Failure modes

| # | Failure | When |
|---|---|---|
| E1 | Ambiguous producing class | deferred, no explicit tag, 0 or ≥2 classes |
| E2 | Cross-class consumption without adapter | consumption boundary |
| E2b | Duplicate adapter pair | channel declaration / consume override |
| E2c | Class-tagged contribution in class-neutral read | consumption boundary |
| E3 | Dataflow cycle | `compose` |
| E4a | Unknown channel reference | `compose` |
| E4b | Duplicate channel name | `compose` |
| E5 | Dedup conflict under `keep = "error"` | channel evaluation |
| E6 | Value access on unresolved deferred contribution | value-demanding operator/consumer |
| E7 | Explicit tag not bound at position | `contribute` |
| E8 | Undeclared deferral (bare config-demanding fn) | `contribute` |
| E9 | Type-contract violation | consumption (executes post-resolution, per value) |
| E10/E10b | Reserved/unknown discipline | `channel` construction; re-validated by `compose` |
| E11 | Deferred in value-mode read with no resolver | `consume` |

Every message names its pinned content fields (golden-tested); exact prose may evolve.

______________________________________________________________________

## Laws

- **L1 — B5 per channel.** Left fold in the pinned canonical traversal under the associative-only
  combine. No silent reorder, no silent dedup.
- **L2 — Join determinism.** Concatenation of inputs' L1 sequences in pinned `inputs` order.
- **L3 — Order preservation.** `map`/`filter`/`scan`/`tee`/`route` preserve (relative) order.
- **L4 — DAG acyclicity at composition time.**
- **L5 — B2 two-stratum.** Reads the graph, never defines it.
- **L6 — Demand-driven.** Unconsumed channels never evaluate.
- **L7 — Dedup: identity-keyed, declared, never silent.** The dual-inclusion pair is never collapsed.
- **L8 — Provenance.** Structured chain recoverable from any record.
- **L9 — Class soundness.** T1–T4, adapters, or a named error — never a silent misclassification.
- **L10 — Non-destructive operators.**
- **L11 — Inbound delivery order.** Native base then inbound deliveries in compose declaration order.
- **L12 — Derived-channel reset.** Attributes never inherited.
- **L13 — Config-dependence is a static structural partition.** Computable at `compose` without
  forcing any value; the sound necessary condition for core membership.

______________________________________________________________________

## Deviations

Refinements/limitations relative to the component spec (`2026-07-05-gen-pipe-component-spec.md`):

- **`sel.entity` / `sel.kind`** are shipped inside gen-pipe (over gen-select's `attrs`), pending the
  gen-select §8 extensions in the pinned dependency. Identity-law-honoring (they take entries/kinds).
- **`producer.classes`** is an accepted field on `contribute`'s producer bundle (the position's class
  bindings), which T2/T4/E7 require — an argument-shape refinement of the §4.2 producer shape.
- **`channel.init`** is exposed (the §2.1 fold seed `foldl combine init …`), an argument-shape
  refinement of the API sketch so an empty channel folds to `init`.
- **`tee` returns an `<op>`** (a delivery descriptor consumed by `compose`) rather than the list of
  target channels; targets are passed in and already exist.
- **Derived-channel base identity** collides for two distinct derivations over the same input+op
  without an explicit `name`; give such channels explicit names (the `declIndex` disambiguates final
  output names, but input references match on the base id).
