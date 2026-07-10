# Demand-driven evaluation (§2.1, §2.4). `run` binds a DAG to a caller-supplied traversal adapter
# (gen-scope's collectionAttr contract shape) and returns a lazy outputs accessor. A channel's value
# at a position is the left fold over its pinned, deduped sequence — native base (self → imports →
# parent, imports in declaration order — HOAG r2 §B5) followed by inbound route/tee deliveries in
# compose declaration order (L11), deduped once, folded once.
#
# Determinism does NOT come from Kahn (1974) KPN semantics — gen-pipe channels have MULTIPLE writers,
# violating Kahn's single-writer condition. It comes from the B5 discipline: pinned canonical
# traversal + associative-only left fold (HOAG r2 §B5, den ISSUES #10).
{
  prelude,
  errors,
  helpers,
  deferred,
  select,
}:
let
  inherit (prelude)
    filter
    concatMap
    map
    head
    elemAt
    length
    range
    genList
    foldl'
    all
    any
    ;
  inherit (helpers) configArgsOf identityKey;
  inherit (select) matchView viewOf;
  inherit (deferred) poison;

  addHopP = c: hop: c.provenance // { hops = c.provenance.hops ++ [ hop ]; };
in
{
  run =
    {
      dag,
      traversal,
    }:
    let
      resolver = traversal.resolveDeferred or null;
      render = traversal.render or helpers.renderCoords;

      # Inbound delivery edges of a channel, already in delivery (compose-declaration) order (L11).
      inbound = name: filter (e: e.to == name) dag.edges;

      # ── per-contribution transforms ──
      chanOf = name: dag.channels.${name};

      mapC =
        f: name: c:
        let
          fConfig = configArgsOf f != [ ];
          outDef = c.deferred || fConfig;
          hop = {
            op = "map";
            channel = name;
          };
        in
        if outDef then
          # Composes into the thunk (§2.3): `deferred fn` becomes `deferred (env: f (fn env))`; a
          # config-reading `f` also defers the output (L13 taint). Value stays a poisoned E6 thunk.
          c
          // {
            channel = chanOf name;
            deferred = true;
            classInvariant = false;
            fn =
              let
                inner = if c.deferred then c.fn else (_: c.value);
              in
              env: f (inner env);
            # arg demand is preserved from a deferred input (f applies post-resolution); a
            # config-reading f over a plain input contributes its own demand.
            argDemand = if c.deferred then c.argDemand else builtins.functionArgs f;
            value = poison {
              channel = name;
              producer = c.producer;
            };
            provenance = addHopP c hop;
          }
        else
          c
          // {
            channel = chanOf name;
            value = f c.value;
            classInvariant = c.classInvariant;
            provenance = addHopP c hop;
          };

      addDeliveryHop =
        c: edge:
        c
        // {
          channel = chanOf edge.to;
          provenance = addHopP c {
            op = edge.op;
            inherit (edge) from to;
          };
        };

      synthetic =
        {
          name,
          value,
          classInvariant,
          position,
          hop,
        }:
        {
          __genPipeContribution = true;
          channel = chanOf name;
          inherit value classInvariant;
          deferred = false;
          fn = null;
          argDemand = null;
          class = null;
          producer = {
            entity = null;
            scope = position;
            aspect = null;
          };
          provenance = {
            base = {
              producer = {
                entity = null;
                scope = position;
                aspect = null;
              };
              rendered = null;
            };
            hops = [ hop ];
          };
        };

      # Value-demanding operators (fold/scan/join-with-combine) require resolved values. The E6 is
      # LAZY — it lives in the synthetic `value` thunk, so the output's metadata (classInvariant flag,
      # provenance) stays readable WITHOUT forcing any contribution value (L13: the class-invariant
      # partition is computable without forcing). Only folding the value throws, naming operator +
      # channel + producer (§2.3).
      e6IfDeferred =
        op: name: seq: folded:
        let
          bad = filter (c: c.deferred) seq;
        in
        if bad != [ ] then
          throw (
            errors.e6 {
              channel = name;
              inherit op;
              producer = (head bad).producer;
            }
          )
        else
          folded;

      foldC =
        ch: d: seq: p:
        synthetic {
          inherit (ch) name;
          value = e6IfDeferred "fold" ch.name seq (foldl' d.f d.init (map (c: c.value) seq));
          classInvariant = all (c: c.classInvariant) seq && configArgsOf d.f == [ ];
          position = p;
          hop = {
            op = "fold";
            channel = ch.name;
            inputs = map (c: c.provenance.base) seq;
          };
        };

      scanC =
        ch: d: seq: p:
        # k-th output (k = 1…n) = fold of the first k inputs; init is never emitted, so an empty
        # input yields an empty output; provenance of the k-th output = the input prefix of length k.
        let
          mkOut =
            k:
            let
              prefixCs = genList (i: elemAt seq i) (k + 1);
            in
            synthetic {
              inherit (ch) name;
              value = e6IfDeferred "scan" ch.name prefixCs (foldl' d.f d.init (map (c: c.value) prefixCs));
              classInvariant = all (c: c.classInvariant) prefixCs && configArgsOf d.f == [ ];
              position = p;
              hop = {
                op = "scan";
                channel = ch.name;
                inputs = map (c: c.provenance.base) prefixCs;
              };
            };
        in
        genList mkOut (length seq);

      overC =
        ch: d: seq: p:
        # `f` applied to the WHOLE value list → a new value list; each element becomes a fresh synthetic
        # contribution at position p (den v1 `for`: `map seed (f (map unwrap values))`). Value-demanding,
        # like fold/scan — but the E6 guard rides the OUTPUT-LIST thunk, not a per-output value thunk:
        # `over`'s cardinality is `length (f values)`, so the deferred guard must resolve before ANY output
        # contribution exists (strict), where fold/scan keep the E6 lazy because their output shape (1 / n)
        # is value-INDEPENDENT. classInvariant composes exactly as fold's: the whole batch is invariant iff
        # every input is and `f` reads no config (L13).
        let
          classInvariant = all (c: c.classInvariant) seq && configArgsOf d.f == [ ];
          inputs = map (c: c.provenance.base) seq;
          outValues = e6IfDeferred "over" ch.name seq (d.f (map (c: c.value) seq));
        in
        map (
          v:
          synthetic {
            inherit (ch) name;
            value = v;
            inherit classInvariant;
            position = p;
            hop = {
              op = "over";
              channel = ch.name;
              inherit inputs;
            };
          }
        ) outValues;

      joinC =
        ch: d: p:
        let
          inNames = d.inputs;
          seqs = map (inName: seqAt inName p) inNames;
          # Output sequence = concatenation of each input's B5-ordered sequence, inputs in
          # list-declaration order (§3 L2). compose never reorders inputs.
          concatenated = concatMap (
            i:
            map (
              c:
              c
              // {
                channel = chanOf ch.name;
                provenance = addHopP c {
                  op = "join";
                  to = ch.name;
                  inputIndex = i;
                };
              }
            ) (elemAt seqs i)
          ) (range 0 (length inNames - 1));
        in
        if d.combine == null then
          concatenated
        else
          [
            (synthetic {
              inherit (ch) name;
              value = e6IfDeferred "join" ch.name concatenated (
                foldl' d.combine.f d.combine.init (map (c: c.value) concatenated)
              );
              classInvariant = all (c: c.classInvariant) concatenated && configArgsOf d.combine.f == [ ];
              position = p;
              hop = {
                op = "join";
                channel = ch.name;
                inputs = map (c: c.provenance.base) concatenated;
              };
            })
          ];

      deriveSeq =
        ch: p:
        let
          d = ch.__derive;
          inName = head d.inputs;
        in
        if d.op == "map" then
          map (mapC d.f ch.name) (seqAt inName p)
        else if d.op == "filter" then
          filter (c: matchView d.p c) (seqAt inName p)
        else if d.op == "fold" then
          [ (foldC ch d (seqAt inName p) p) ]
        else if d.op == "scan" then
          scanC ch d (seqAt inName p) p
        else if d.op == "over" then
          overC ch d (seqAt inName p) p
        else
          joinC ch d p;

      deliverSeq =
        edge: p:
        let
          src = seqAt edge.from p;
          matched = filter (c: matchView edge.select c) src;
        in
        map (c: addDeliveryHop c edge) matched;

      # Dedup (§4.3, L7): identity-keyed, declared, never silent. Returns kept sequence + drop records.
      dedupResult =
        ch: full:
        if ch.dedup == null then
          {
            seq = full;
            drops = [ ];
          }
        else
          let
            keyKind = ch.dedup.key or "identity";
            keep = ch.dedup.keep or "first";
            keyOf =
              c: if keyKind == "identity" then identityKey c.producer else builtins.toJSON (keyKind (viewOf c));
            indexed = genList (i: {
              c = elemAt full i;
              key = keyOf (elemAt full i);
              i = i;
            }) (length full);
          in
          if keep == "last" then
            # keep = "last": the LAST occurrence of each key survives in its own position; every
            # earlier occurrence becomes a recorded drop whose kept survivor is that last contribution.
            # Computed directly from the last index per key — no in-place nulling, so a third
            # occurrence never dereferences a removed slot, and `kept` is always the true survivor
            # (L7 per-drop provenance, correct for any duplicate multiplicity).
            let
              lastIdx = foldl' (m: e: m // { ${e.key} = e.i; }) { } indexed;
              survives = e: lastIdx.${e.key} == e.i;
              survivorBaseOf = e: (elemAt full lastIdx.${e.key}).provenance.base;
            in
            {
              seq = map (e: e.c) (filter survives indexed);
              drops = map (e: {
                key = e.key;
                kept = survivorBaseOf e;
                dropped = [ e.c.provenance.base ];
              }) (filter (e: !survives e) indexed);
            }
          else
            # keep = "first" | "error": one incremental pass over the pinned order. keep = "first" is
            # pinned-order stable (the earliest occurrence survives in place); keep = "error" raises E5
            # on the first duplicate.
            let
              step =
                acc: e:
                let
                  dup = builtins.elem e.key acc.seen;
                  keptFor = head (filter (x: x.key == e.key) acc.kept);
                in
                if !dup then
                  acc
                  // {
                    seen = acc.seen ++ [ e.key ];
                    kept = acc.kept ++ [ e ];
                    out = acc.out ++ [ e.c ];
                  }
                else if keep == "error" then
                  throw (
                    errors.e5 {
                      channel = ch.name;
                      key = e.key;
                      kept = keptFor.c.producer;
                      dropped = e.c.producer;
                    }
                  )
                else
                  # keep = "first": drop this later occurrence; the earlier survivor is kept.
                  acc
                  // {
                    drops = acc.drops ++ [
                      {
                        key = e.key;
                        kept = keptFor.c.provenance.base;
                        dropped = [ e.c.provenance.base ];
                      }
                    ];
                  };
              folded = foldl' step {
                seen = [ ];
                kept = [ ];
                out = [ ];
                drops = [ ];
              } indexed;
            in
            {
              seq = folded.out;
              inherit (folded) drops;
            };

      # base(ch,p): for a declared channel, the contributions attached via contributionsAt enumerated
      # in the traversal pin (self → imports → parent; imports in declaration order — the gen-scope
      # collectionAttr public contract, HOAG r2 §B5 rule 1). `order p` supplies the visibility
      # sequence; contributionsAt is consulted for DECLARED channels only (derived channel names are
      # never queried against the adapter).
      baseSeq =
        ch: p:
        if ch.__derived or false then
          deriveSeq ch p
        else
          concatMap (vp: traversal.contributionsAt vp ch.name) (traversal.order p);

      seqAt =
        name: p:
        let
          ch = chanOf name;
          full = baseSeq ch p ++ concatMap (edge: deliverSeq edge p) (inbound name);
        in
        (dedupResult ch full).seq;

      channelValue = ch: seq: foldl' ch.combine ch.init (map (c: c.value) seq);

      traceAt =
        name: p:
        let
          ch = chanOf name;
          full = baseSeq ch p ++ concatMap (edge: deliverSeq edge p) (inbound name);
          dr = dedupResult ch full;
        in
        {
          channel = name;
          position = p;
          sequence = map (c: c.provenance.base) dr.seq;
          deduped = dr.drops;
          # Channel-level trace carries no adapter entries: adaptation is class-relative (§2.6.5) and
          # occurs only at a consuming class. `traceOf { outputs; at; channel; class; }` recomputes the
          # `adapted` records for a given consuming class (§4.6, L9 "never silent"); `consume` appends
          # the matching per-contribution `adapted` provenance hop on the same events.
          adapted = [ ];
          routedIn = map (edge: {
            inherit (edge) from declIndex;
            via = edge.op;
            count = length (filter (c: matchView edge.select c) (seqAt edge.from p));
          }) (inbound name);
        };

      outputs = {
        at =
          p:
          builtins.mapAttrs (name: ch: {
            contributions = seqAt name p;
            values = channelValue ch (seqAt name p);
            trace = traceAt name p;
            classInvariant = map (c: c.classInvariant) (seqAt name p);
          }) dag.channels;
        __resolveDeferred = resolver;
        __render = render;
        __dag = dag;
      };
    in
    outputs;
}
