# law-adapter (L9). Cross-class consumption occurs only through a declared adapter: a contribution
# whose tag ≠ the consuming class is matched by (from,to) identity, re-tagged, an `adapted` hop
# appended (never silent), and the coercion applied (post-resolution). Zero matches ⇒ E2; a duplicate
# (from,to) pair ⇒ E2b; a class-tagged contribution in a class-neutral read ⇒ E2c.
{
  genPipe,
  ...
}:
let
  f = import ./_fixtures/common.nix { inherit genPipe; };
  inherit (f)
    host
    clsNixos
    clsHm
    ;
  inherit (genPipe)
    channel
    contribute
    compose
    run
    consume
    provenanceOf
    ;

  # The adapter fn receives the RESOLVED value and the contribution's provenance chain (read-only).
  # It reads provenance.base to prove the chain is passed.
  adapter = {
    from = clsHm;
    to = clsNixos;
    fn = value: provenance: value ++ [ provenance.base.producer.entity.id_hash ];
  };
  withAdapter = channel {
    name = "c";
    class = {
      expect = clsNixos;
      adapters = [ adapter ];
    };
  };
  noAdapter = channel { name = "c"; };

  mk =
    ch: cls:
    contribute {
      channel = ch;
      value = [ "v" ];
      class = cls;
      producer = {
        entity = host "axon-01";
        scope.host = host "axon-01";
        aspect = f.aspect "A";
        classes = [ cls ];
      };
    };

  runW =
    ch: contribs:
    run {
      dag = compose [ ch ];
      traversal = f.mkTraversal { table.p.c = contribs; };
    };

  outAdapter = runW withAdapter [
    (mk withAdapter clsNixos)
    (mk withAdapter clsHm)
  ];
  outNo = runW noAdapter [ (mk noAdapter clsHm) ];

  consumed = consume {
    outputs = outAdapter;
    at = "p";
    channel = withAdapter;
    class = clsNixos;
    mode = "values";
  };
  records = consume {
    outputs = outAdapter;
    at = "p";
    channel = withAdapter;
    class = clsNixos;
    mode = "records";
  };
  tri = builtins.tryEval;
in
{
  flake.tests.law-adapter = {
    # nixos contribution passes untouched; hm contribution is coerced + re-tagged nixos.
    test-adapter-coerces = {
      expr = consumed;
      expected = [
        [ "v" ]
        [
          "v"
          "h:host:axon-01"
        ]
      ];
    };
    # the adapted contribution carries an `adapted` provenance hop (never silent).
    test-adapted-hop = {
      expr =
        let
          hmRecord = builtins.elemAt records 1;
          hops = (provenanceOf hmRecord).hops;
        in
        builtins.any (h: h.op or null == "adapted") hops;
      expected = true;
    };
    # the adapted record is re-tagged to the consuming class.
    test-adapted-retag = {
      expr = (builtins.elemAt records 1).class.id_hash;
      expected = "cls:nixos";
    };
    # without a declared adapter, the cross-class contribution is E2.
    test-e2-no-adapter = {
      expr =
        (tri (
          builtins.deepSeq (consume {
            outputs = outNo;
            at = "p";
            channel = noAdapter;
            class = clsNixos;
            mode = "values";
          }) true
        )).success;
      expected = false;
    };
    # class-neutral read receiving a class-tagged contribution ⇒ E2c.
    test-e2c-neutral-read = {
      expr =
        (tri (
          builtins.deepSeq (consume {
            outputs = outNo;
            at = "p";
            channel = noAdapter;
            class = null;
            mode = "values";
          }) true
        )).success;
      expected = false;
    };
    # duplicate (from,to) adapter pair ⇒ E2b (here via a consume-site extension duplicating the pair).
    test-e2b-duplicate-pair = {
      expr =
        (tri (
          builtins.deepSeq (consume {
            outputs = outAdapter;
            at = "p";
            channel = withAdapter;
            class = clsNixos;
            adapters = [ adapter ]; # duplicates the channel-declared (hm→nixos) pair
            mode = "values";
          }) true
        )).success;
      expected = false;
    };
    # consume-site adapter EXTENSION: a channel with no adapter, coerced by a read-local one.
    test-consume-site-extension = {
      expr = consume {
        outputs = outNo;
        at = "p";
        channel = noAdapter;
        class = clsNixos;
        adapters = [
          {
            from = clsHm;
            to = clsNixos;
            fn = value: _: value ++ [ "local" ];
          }
        ];
        mode = "values";
      };
      expected = [
        [
          "v"
          "local"
        ]
      ];
    };
  };
}
