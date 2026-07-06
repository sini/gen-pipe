# DAG composition + validation (§2.4, §2.5). `compose` takes the declaration list (channels +
# operators, any order — they carry their own edges) and returns a validated DAG value. All checks
# are definition-time and force DAG STRUCTURE only, never contribution values (L4). Naming for
# derived channels is assigned here per §2.3a (declIndex from the decls-list position).
{
  prelude,
  errors,
  helpers,
  channel,
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
    elem
    genList
    foldl'
    attrNames
    ;
  inherit (helpers) entryEq;

  inherit (prelude) tail;
  isChannel = d: d.__genPipeChannel or false;
  isOp = d: d.__genPipeOp or false;

  # The immediate channel seeds of a decl (a channel itself; an op's from/to/output targets). Derive
  # inputs are reached transitively by the cycle-safe worklist in `compose` (a cyclic derive graph
  # must terminate collection so E3 can fire, rather than looping).
  seedsOfDecl =
    d:
    if isChannel d then
      [ d ]
    else if d.op == "route" then
      [
        d.from
        d.to
      ]
    # tee
    else
      [ d.from ] ++ map (o: o.to) d.outputs;
in
{
  compose =
    decls:
    let
      n = length decls;
      idxs = range 0 (n - 1);

      # ── channel collection (cycle-safe worklist; unique by id, first occurrence wins) ──
      collected =
        let
          go =
            frontier: acc:
            if frontier == [ ] then
              acc
            else
              let
                ch = head frontier;
                rest = tail frontier;
              in
              if acc.byId ? ${ch.id} then
                go rest acc
              else
                go (rest ++ (ch.__derive.inputs or [ ])) {
                  byId = acc.byId // {
                    ${ch.id} = ch;
                  };
                  order = acc.order ++ [ ch.id ];
                };
        in
        go (concatMap seedsOfDecl decls) {
          byId = { };
          order = [ ];
        };
      byId = collected.byId;
      orderedIds = collected.order;

      # ids of channels appearing DIRECTLY in decls — the "declaration set" E4a is checked against.
      declaredIds = map (d: d.id) (filter isChannel decls);

      # declIndex = the channel's index in the decls list (§2.3a); embedded-only channels (never a
      # direct decl) fall back to a stable position after the decls range.
      declIndexOf =
        id:
        let
          direct = filter (i: isChannel (elemAt decls i) && (elemAt decls i).id == id) idxs;
        in
        if direct != [ ] then
          head direct
        else
          n
          + (foldl' (acc: k: if elemAt orderedIds k == id then k else acc) 0 (
            range 0 (length orderedIds - 1)
          ));

      # Final name (§2.3a): explicit/declared name, else "<inputName>.<op>.<declIndex>"
      # ("join.<declIndex>" for multi-input join).
      nameOf =
        id:
        let
          ch = byId.${id};
        in
        if !(ch.__derived or false) then
          ch.id
        else if ch.name != null then
          ch.name
        else if ch.op == "join" then
          "join.${toString (declIndexOf id)}"
        else
          "${nameOf (head ch.__derive.inputs).id}.${ch.op}.${toString (declIndexOf id)}";

      finalNames = map (id: {
        inherit id;
        name = nameOf id;
      }) orderedIds;

      # E4b — duplicate final names (an explicit-vs-derived collision lands here too).
      dupCheck = foldl' (
        acc: e:
        if elem e.name acc.seen then acc // { dup = e.name; } else acc // { seen = acc.seen ++ [ e.name ]; }
      ) { seen = [ ]; } finalNames;

      # ── channels attrset keyed by final name ──
      channels = foldl' (
        acc: e:
        let
          ch = byId.${e.id};
          validated = ch // {
            name = e.name;
            merge = channel.validateMerge e.name ch.merge;
          };
          resolved =
            if ch.__derived or false then
              validated
              // {
                __derive = ch.__derive // {
                  inputs = map (i: nameOf i.id) ch.__derive.inputs;
                };
              }
            else
              validated;
        in
        acc // { ${e.name} = resolved; }
      ) { } finalNames;

      idToName = foldl' (acc: e: acc // { ${e.id} = e.name; }) { } finalNames;

      # ── E4a: every referenced channel is in the declaration set ──
      refCheck =
        let
          derivedRefs = concatMap (
            id:
            let
              ch = byId.${id};
            in
            if (ch.__derived or false) && elem id declaredIds then
              map (i: {
                op = ch.op;
                inherit (i) id;
              }) ch.__derive.inputs
            else
              [ ]
          ) orderedIds;
          opRefs = concatMap (
            d:
            if d.op == "route" then
              [
                {
                  op = "route";
                  inherit (d.from) id;
                }
                {
                  op = "route";
                  inherit (d.to) id;
                }
              ]
            else
              [
                {
                  op = "tee";
                  inherit (d.from) id;
                }
              ]
              ++ map (o: {
                op = "tee";
                inherit (o.to) id;
              }) d.outputs
          ) (filter isOp decls);
          bad = filter (r: !(elem r.id declaredIds)) (derivedRefs ++ opRefs);
        in
        if bad != [ ] then
          throw (
            errors.e4a {
              inherit ((head bad)) op;
              name = idToName.${(head bad).id} or (head bad).id;
            }
          )
        else
          true;

      # ── delivery edges (route/tee), in compose declaration order (L11) ──
      opsWithIdx = filter (e: isOp (elemAt decls e.i)) (
        map (i: {
          i = i;
          d = elemAt decls i;
        }) idxs
      );
      rawEdges = concatMap (
        e:
        let
          d = e.d;
        in
        if d.op == "route" then
          [
            {
              op = "route";
              from = idToName.${d.from.id};
              to = idToName.${d.to.id};
              inherit (d) select;
              declIndex = e.i;
              sub = 0;
            }
          ]
        else
          genList (k: {
            op = "tee";
            from = idToName.${d.from.id};
            to = idToName.${(elemAt d.outputs k).to.id};
            select = (elemAt d.outputs k).select or null;
            declIndex = e.i;
            sub = k;
          }) (length d.outputs)
      ) opsWithIdx;
      # already in (declIndex, sub) order since opsWithIdx follows decls order.
      edges = rawEdges;

      # ── E2b: duplicate adapter (from,to) pair on any channel ──
      adapterDupCheck =
        let
          perChannel = concatMap (
            name:
            let
              ads = channels.${name}.class.adapters;
              pairs = map (a: { inherit (a) from to; }) ads;
              findDup = foldl' (
                acc: p:
                if builtins.any (q: entryEq q.from p.from && entryEq q.to p.to) acc.seen then
                  acc // { dup = p; }
                else
                  acc // { seen = acc.seen ++ [ p ]; }
              ) { seen = [ ]; } pairs;
            in
            if findDup ? dup then
              [
                {
                  inherit name;
                  inherit (findDup) dup;
                }
              ]
            else
              [ ]
          ) (attrNames channels);
        in
        if perChannel != [ ] then
          throw (
            errors.e2b {
              channel = (head perChannel).name;
              inherit ((head perChannel).dup) from to;
            }
          )
        else
          true;

      # ── E3: acyclicity over derive + delivery dependency edges ──
      # preds[node] = channels that must precede it (its derive inputs + delivery sources).
      derivePreds = concatMap (
        name:
        let
          ch = channels.${name};
        in
        if ch.__derived or false then
          map (inp: {
            from = inp;
            to = name;
          }) ch.__derive.inputs
        else
          [ ]
      ) (attrNames channels);
      deliveryPreds = map (edge: {
        from = edge.from;
        to = edge.to;
      }) edges;
      depPairs = derivePreds ++ deliveryPreds;
      before = a: b: builtins.any (p: p.from == a && p.to == b) depPairs;
      topoResult = prelude.toposort before (attrNames channels);
      cycleCheck =
        if topoResult ? cycle then
          let
            cyc = topoResult.cycle;
            opsInCycle = prelude.unique (
              map (p: p.op or "derive") (filter (edge: elem edge.from cyc && elem edge.to cyc) edges)
              ++ map (name: channels.${name}.op or "derive") (
                filter (name: (channels.${name}.__derived or false) && elem name cyc) cyc
              )
            );
          in
          throw (
            errors.e3 {
              cycle = cyc;
              ops = if opsInCycle == [ ] then [ "derive" ] else opsInCycle;
            }
          )
        else
          true;

      # ── E2 static class coverage (statically decidable delivery/join edges) ──
      staticClassCheck =
        let
          bad = filter (
            edge:
            let
              s = channels.${edge.from}.class.expect or null;
              t = channels.${edge.to}.class.expect or null;
              hasAdapter = builtins.any (
                a: entryEq a.from s && entryEq a.to t
              ) channels.${edge.to}.class.adapters;
            in
            s != null && t != null && !(entryEq s t) && !hasAdapter
          ) edges;
        in
        if bad != [ ] then
          let
            edge = head bad;
          in
          throw (
            errors.e2 {
              channel = edge.to;
              consumingClass = channels.${edge.to}.class.expect;
              tag = channels.${edge.from}.class.expect;
              producer = {
                entity = null;
                scope = null;
                aspect = null;
              };
            }
          )
        else
          true;

      guards = builtins.deepSeq [
        refCheck
        adapterDupCheck
        cycleCheck
        staticClassCheck
        (if dupCheck ? dup then throw (errors.e4b { name = dupCheck.dup; }) else true)
      ] true;
    in
    assert guards;
    {
      __genPipeDag = true;
      inherit channels edges declaredIds;
      topo = topoResult.result or (attrNames channels);
    };
}
