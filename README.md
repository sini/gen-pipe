# gen-pipe — scoped channels + dataflow algebra

[![CI](https://github.com/sini/gen-pipe/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-pipe/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

The content-agnostic **dataflow algebra for scoped channels**. A *channel* is a typed, named accumulation lane; its value *at a scope position* is a deterministic fold over the contributions visible from that position under a pinned traversal. Operators (`map`, `filter`, `fold`, `scan`, `route`, `join`, `tee`) connect channels into a **dataflow DAG**, validated at composition time and evaluated demand-driven.

gen-pipe supplies three guarantees that den v1's pipe machinery enforced only by convention:

1. **Determinism as law** — B5 per channel: pinned traversal (self → imports → parent), associative-only combine, no silent reorder or dedup.
1. **Provenance as data** — every contribution carries its producer as structured registry-entry identities (entity, scope coordinates, aspect); operators extend the chain; consumers can interrogate it.
1. **Class as type** — contributions are class-tagged at emission; a deferred (config-demanding) contribution's `config` means *the producing class's config at the producing scope*; cross-class consumption requires a declared adapter; class ambiguity is a definition-time error naming the producer and channel.

Plus a fourth, for the class-share build path: **config-dependence as a static flag** — every contribution and derived output carries `classInvariant`, derived from arg-shape and composed through operators at composition time (never a runtime discovery).

## Table of Contents

- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Quick Start](#quick-start)
- [The dual-inclusion question](#the-dual-inclusion-question)
- [API Reference](#api-reference)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Overview

A channel's value at a position `p` is:

```
sequence(ch, p) = base(ch, p) ++ delivered(e₁, p) ++ … ++ delivered(eₙ, p)
value(ch, p)    = foldl combine init (postDedup (sequence ch p))
```

- `base` is the channel's native sequence — for a declared channel, `traversal.contributionsAt` enumerated in the traversal pin (**self → imports → parent**, imports in declaration order — gen-scope's `collectionAttr` public contract). For a derived channel, the defining operator's output.
- `e₁ … eₙ` are the inbound `route`/`tee` delivery edges, in **compose declaration order**, each an order-preserving `select`-matched subsequence of its source at the **same position**.
- `postDedup` applies the channel's declared, traced dedup policy (identity if none). `combine` is associative-only; the default is list concatenation, so the default channel value is the ordered contribution list.

gen-pipe does **not** evaluate NixOS/home-manager configs, discover writers, or construct scope graphs — those reach it through a caller-supplied traversal adapter (den-hoag's projection of the scope graph). It reads the graph and produces plain data; no output can feed graph structure (the two-stratum discipline).

## Gen Ecosystem

| Library | Role |
|---------|------|
| [gen-prelude](https://github.com/sini/gen-prelude) | Pure nixpkgs-lib-free utility base (builtins re-exports + vendored lib utils) |
| [gen-select](https://github.com/sini/gen-select) | Selector algebra (pattern matching over graph positions) — routing/consumption predicates |
| [gen-scope](https://github.com/sini/gen-scope) | HOAG scope-graph evaluator; supplies the `collectionAttr` traversal contract gen-pipe consumes |
| [gen-pipe](https://github.com/sini/gen-pipe) | **This lib** — scoped channels + dataflow algebra |

Class B: L1-only dependencies, nothing upward, nixpkgs-lib-free. gen-schema is **not** a dependency — registry entries are opaque `id_hash`-bearing values to gen-pipe (duck-typed).

## Quick Start

```nix
let
  genPipe = import (builtins.fetchGit "https://github.com/sini/gen-pipe") { };
  inherit (genPipe) channel contribute compose run sel;

  # 1. declare a channel
  backends = channel { name = "http-backends"; };

  # 2. build contributions (den-hoag does this per producing position)
  c = contribute {
    channel = backends;
    value = [ "10.0.0.1" ];
    producer = { entity = hostEntry; scope = { host = hostEntry; }; aspect = aspectEntry; };
  };

  # 3. compose the DAG
  dag = compose [ backends ];

  # 4. run against a traversal adapter (gen-scope's collectionAttr shape)
  outputs = run {
    inherit dag;
    traversal = {
      order = p: [ p ];                              # self → imports → parent
      contributionsAt = p: chName: [ c ];
      classesOf = p: [ ];
      render = coords: "…";
    };
  };
in
  (outputs.at position)."http-backends".values     # ⇒ [ "10.0.0.1" ]
```

## The dual-inclusion question

> An aspect `A` contributes to channel `C`. `A` is included by BOTH user `sini` and host `axon-01`. What class is the contribution? What does `config` mean inside it? How does it fail?

**Dual inclusion never yields one ambiguous contribution — it yields two, one per (aspect, producing position) pair, each class-tagged by its own producing position.** The user-position contribution is tagged `home-manager`; the host-position one `nixos`. Inside a deferred value, `config` means the *producing* class's config at the *producing* scope (never the consuming module's) — which is what makes cross-scope consumption sound. The identity key includes the producing scope coordinates, so the pair is **never** a dedup duplicate.

It fails loudly, never silently: an ambiguous producing class (0 or ≥2 classes, no explicit tag) is `E1`; cross-class consumption without an adapter is `E2`; a bare config-demanding function without the `deferred` wrapper is `E8`. See [REFERENCE.md](./REFERENCE.md) §Class semantics.

## API Reference

Full API in [REFERENCE.md](./REFERENCE.md). Surface:

```nix
genPipe = {
  channel  = { name, type ?, merge ?, combine ?, init ?, dedup ?, class ? }: <channel>;
  contribute = { channel, value, producer, class ? }: <contribution>;
  deferred = fn: <deferredValue>;

  map    = f: <channel>: <channel>;           # or map { f, name ?, type ?, dedup ?, class ? }
  filter = p: <channel>: <channel>;
  fold   = { f, init, ... }: <channel>: <channel>;
  scan   = { f, init, ... }: <channel>: <channel>;
  route  = { from, select, to }: <op>;
  join   = { inputs, combine ?, ... }: <channel>;
  tee    = { from, outputs }: <op>;

  compose = decls: <dag>;
  run     = { dag, traversal }: <outputs>;
  consume = { outputs, at, channel, class ?, adapters ?, select ?, mode ? }: [ value ] | [ record ];

  provenanceOf = record: <chain>;
  traceOf      = { outputs, at, channel }: <trace>;
  sel = <gen-select constructors> // { entity; kind; all; };
};
```

All public entry points pass and receive **values** — channel values, contribution records, registry entries — never `"kind:name"` strings (the identity law). Strings appear only as internal keys and in rendered error/display text.

## Testing

```bash
cd ci && nix-unit --flake .#tests            # or: nix flake check
```

Every law (L1–L13) is a named test group; error content is golden-tested; the goldens re-run against a real gen-scope graph in `integration-gen-scope`.

## Theoretical Foundations

- **Kahn (1974), KPN** — *informed-by only*. gen-pipe channels have **multiple writers**, violating Kahn's single-writer condition (the source of KPN determinism). gen-pipe's determinism therefore does **not** come from KPN semantics — it comes from the B5 discipline: pinned canonical traversal + associative-only left fold (HOAG r2 §B5, den ISSUES #10). This caveat is load-bearing.
- **van Antwerpen et al. (2016), Statix** (via HOAG r2 §B2) — the two-stratum discipline that makes reading an under-construction scope graph sound. gen-pipe realizes the *consumer side* of that condition, not the resolution calculus.
- **Cheney, Chiticariu & Tan (2009), "Provenance in Databases: Why, How, and Where"** — the provenance chain is lineage/where-provenance-shaped. gen-pipe does not implement the semiring-annotated generality of Green–Karvounarakis–Tannen (2007); the survey is cited, not the semiring framework, to keep the claim honest.

The producer-class deferral semantics trace to engineering precedent (den v1 PR #623, HOAG r2's `pipe.withConfig` thunk contract), cited as design provenance.
