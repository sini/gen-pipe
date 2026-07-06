# law-consume (L9 + type). The checked read: the class-discipline matrix (tag = class / null /
# adapter / E2 / E2c), gen-select `select` over producer views, the channel `type` contract (lazy per
# value, E9, executing post-resolution), and the mode matrix ("values" resolves via resolveDeferred,
# "records" yields §4.8 records whose `resolve` applies the composed checks; a resolved contribution's
# `resolve` ignores its argument).
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f)
    host
    user
    clsNixos
    ;
  inherit (genPipe)
    channel
    contribute
    compose
    run
    consume
    sel
    ;

  typed = channel {
    name = "c";
    type = {
      check = v: builtins.isList v;
      description = "must be a list";
    };
  };
  plain = channel { name = "c"; };

  mk =
    ch:
    {
      value,
      ent,
      cls ? null,
      classes ? [ ],
    }:
    contribute {
      channel = ch;
      inherit value;
      class = cls;
      producer = {
        entity = ent;
        scope.host = host "axon-01";
        aspect = f.aspect "A";
        inherit classes;
      };
    };

  # neutral contributions from two entity kinds (host vs user) for selector matching
  cHost = mk plain {
    value = [ "H" ];
    ent = host "axon-01";
  };
  cUser = mk plain {
    value = [ "U" ];
    ent = user "sini";
  };
  outSel = run {
    dag = compose [ plain ];
    traversal = f.mkTraversal {
      table.p.c = [
        cHost
        cUser
      ];
    };
  };

  # a type-violating contribution (scalar, not a list)
  bad = mk typed {
    value = "not-a-list";
    ent = host "axon-01";
  };
  good = mk typed {
    value = [ "ok" ];
    ent = host "axon-01";
  };
  outType = run {
    dag = compose [ typed ];
    traversal = f.mkTraversal {
      table.p.c = [
        good
        bad
      ];
    };
  };

  tri = builtins.tryEval;
in
{
  flake.tests.law-consume = {
    # neutral read of neutral contributions passes.
    test-neutral-read = {
      expr = consume {
        outputs = outSel;
        at = "p";
        channel = plain;
        class = null;
        mode = "values";
      };
      expected = [
        [ "H" ]
        [ "U" ]
      ];
    };
    # select by entity identity (sel.entity).
    test-select-entity = {
      expr = consume {
        outputs = outSel;
        at = "p";
        channel = plain;
        select = sel.entity (user "sini");
        mode = "values";
      };
      expected = [ [ "U" ] ];
    };
    # select by kind (sel.kind) — all host-kind producers.
    test-select-kind = {
      expr = consume {
        outputs = outSel;
        at = "p";
        channel = plain;
        select = sel.kind "host";
        mode = "values";
      };
      expected = [ [ "H" ] ];
    };

    # type contract: the good value passes.
    test-type-good = {
      expr = builtins.head (consume {
        outputs = outType;
        at = "p";
        channel = typed;
        select = sel.entity (host "axon-01");
        mode = "values";
      });
      expected = [ "ok" ];
    };
    # type contract violation ⇒ E9, per value, lazily.
    test-type-e9 = {
      expr =
        (tri (
          builtins.deepSeq (consume {
            outputs = outType;
            at = "p";
            channel = typed;
            mode = "values";
          }) true
        )).success;
      expected = false;
    };

    # records mode: a resolved (non-deferred) contribution yields a record whose `resolve` ignores
    # its argument and returns the already-checked value.
    test-records-constant-resolve = {
      expr =
        let
          recs = consume {
            outputs = outSel;
            at = "p";
            channel = plain;
            class = null;
            mode = "records";
          };
          r0 = builtins.head recs;
        in
        {
          viaResolve = r0.resolve { anything = true; };
          deferred = r0.deferred;
        };
      expected = {
        viaResolve = [ "H" ];
        deferred = false;
      };
    };
  };
}
