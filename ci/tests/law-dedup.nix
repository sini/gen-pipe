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
  };
}
