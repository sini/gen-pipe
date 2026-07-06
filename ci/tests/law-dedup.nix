# law-dedup (L7). Dedup applies only when the channel declares a policy. The default identity key is
# (producer.entity.id_hash, producer.scope coords) — so the dual-inclusion pair (same aspect,
# different producing positions) is NEVER collapsed. Every drop is recorded in the trace; keep=first
# is pinned-order stable; keep=error raises E5.
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f)
    contribHost
    contribUser
    host
    ;
  inherit (genPipe)
    channel
    contribute
    compose
    run
    traceOf
    deferred
    ;

  mkChan =
    dedup:
    channel {
      name = "c";
      inherit dedup;
    };
  runWith =
    { dedup, contribs }:
    run {
      dag = compose [ (mkChan dedup) ];
      traversal = f.mkTraversal { table.p.c = contribs; };
    };

  # two contributions with the SAME producer identity (dup under identity key)
  ch = mkChan {
    key = "identity";
    keep = "first";
  };
  dupA = contribHost {
    channel = ch;
    value = [ "a" ];
    h = "h1";
    aspect = "x";
  };
  dupB = contribHost {
    channel = ch;
    value = [ "b" ];
    h = "h1";
    aspect = "x";
  }; # same (entity,scope)
  dupC = contribHost {
    channel = ch;
    value = [ "d" ];
    h = "h1";
    aspect = "x";
  }; # same (entity,scope) — a THIRD occurrence of the identity key
  distinct = contribHost {
    channel = ch;
    value = [ "c" ];
    h = "h2";
    aspect = "y";
  };

  # dual-inclusion pair: same aspect, DIFFERENT producing positions (host vs user)
  duHost = contribHost {
    channel = ch;
    value = [ "H" ];
    h = "axon-01";
    aspect = "A";
  };
  duUser = contribUser {
    channel = ch;
    value = [ "U" ];
    h = "axon-01";
    u = "sini";
    aspect = "A";
  };

  keepFirst = runWith {
    dedup = {
      key = "identity";
      keep = "first";
    };
    contribs = [
      dupA
      distinct
      dupB
    ];
  };
  noPolicy = runWith {
    dedup = null;
    contribs = [
      dupA
      dupB
    ];
  };
  dualIncl = runWith {
    dedup = {
      key = "identity";
      keep = "first";
    };
    contribs = [
      duHost
      duUser
    ];
  };

  # keep = "last" over THREE identity-key duplicates: the last (dupC) survives; the two earlier
  # occurrences are dropped. Exercises the 3+-duplicate path (a second drop under keep=last must not
  # dereference the removed earlier survivor).
  keepLast = runWith {
    dedup = {
      key = "identity";
      keep = "last";
    };
    contribs = [
      dupA
      dupB
      dupC
    ];
  };

  # keep = "last" with a CUSTOM key that collapses three DISTINCT producers to one key. The survivor
  # is the last producer (hC); every drop's `kept` provenance must name that last survivor, not the
  # first — the per-drop provenance L7 requires.
  keepLastCustom = runWith {
    dedup = {
      key = view: builtins.head view.value;
      keep = "last";
    };
    contribs = [
      (contribHost {
        channel = ch;
        value = [ "k" ];
        h = "hA";
        aspect = "1";
      })
      (contribHost {
        channel = ch;
        value = [ "k" ];
        h = "hB";
        aspect = "2";
      })
      (contribHost {
        channel = ch;
        value = [ "k" ];
        h = "hC";
        aspect = "3";
      })
    ];
  };
in
{
  flake.tests.law-dedup = {
    # keep=first: the later duplicate (dupB) is dropped, pinned order preserved.
    test-keep-first = {
      expr = (keepFirst.at "p").c.values;
      expected = [
        "a"
        "c"
      ];
    };
    # the drop is recorded in the trace with both producers.
    test-drop-recorded = {
      expr =
        let
          t = traceOf {
            outputs = keepFirst;
            at = "p";
            channel = ch;
          };
        in
        builtins.length t.deduped;
      expected = 1;
    };
    # no policy ⇒ duplicates preserved.
    test-no-policy-keeps-dups = {
      expr = (noPolicy.at "p").c.values;
      expected = [
        "a"
        "b"
      ];
    };
    # DUAL-INCLUSION pair survives dedup: distinct producing positions ⇒ distinct identity keys.
    test-dual-inclusion-survives = {
      expr = (dualIncl.at "p").c.values;
      expected = [
        "H"
        "U"
      ];
    };
    # keep=error ⇒ E5 when a duplicate is present.
    test-keep-error-raises-e5 = {
      expr =
        (builtins.tryEval
          (
            (runWith {
              dedup = {
                key = "identity";
                keep = "error";
              };
              contribs = [
                dupA
                dupB
              ];
            }).at
            "p"
          ).c.values
        ).success;
      expected = false;
    };
    # custom key function over the view (metadata-safe).
    test-custom-key = {
      expr =
        (
          (runWith {
            dedup = {
              key = view: builtins.head view.value;
              keep = "first";
            };
            contribs = [
              (contribHost {
                channel = ch;
                value = [ "k" ];
                h = "hA";
                aspect = "1";
              })
              (contribHost {
                channel = ch;
                value = [ "k" ];
                h = "hB";
                aspect = "2";
              })
            ];
          }).at
          "p"
        ).c.values;
      expected = [ "k" ];
    };
    # keep=last over three identity duplicates: the last occurrence survives (no crash on the 3rd).
    test-keep-last-survivor = {
      expr = (keepLast.at "p").c.values;
      expected = [ "d" ];
    };
    # both earlier occurrences are recorded as drops.
    test-keep-last-drops-recorded = {
      expr =
        let
          t = traceOf {
            outputs = keepLast;
            at = "p";
            channel = ch;
          };
        in
        builtins.length t.deduped;
      expected = 2;
    };
    # every drop's `kept` names the true (last) survivor — not the first occurrence (L7 per-drop
    # provenance). The custom key collapses three distinct producers, so the survivor is identifiable.
    test-keep-last-kept-is-survivor = {
      expr =
        let
          t = traceOf {
            outputs = keepLastCustom;
            at = "p";
            channel = ch;
          };
        in
        builtins.map (d: d.kept.producer.entity.id_hash) t.deduped;
      expected = [
        "h:host:hC"
        "h:host:hC"
      ];
    };
    # custom key touching a deferred contribution's .value ⇒ E6 (the poisoned-thunk path through the
    # dedup key function; forced via the trace, which computes keys but never folds values).
    test-custom-key-deferred-e6 = {
      expr =
        (builtins.tryEval (
          builtins.deepSeq (traceOf {
            outputs = runWith {
              dedup = {
                key = view: builtins.head view.value;
                keep = "first";
              };
              contribs = [
                (contribHost {
                  channel = ch;
                  value = deferred ({ config }: [ config.x ]);
                  h = "hA";
                  aspect = "1";
                })
                (contribHost {
                  channel = ch;
                  value = deferred ({ config }: [ config.y ]);
                  h = "hB";
                  aspect = "2";
                })
              ];
            };
            at = "p";
            channel = ch;
          }) true
        )).success;
      expected = false;
    };
  };
}
