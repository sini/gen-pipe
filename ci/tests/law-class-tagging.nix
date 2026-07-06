# law-class-tagging (L9). Tagging follows T1–T4 exactly: T1 explicit tag wins (must be bound at the
# position, else E7); T2 a unique-class position tags with that class; T3 plain data is class-neutral
# (null); T4 a deferred contribution at a 0- or ≥2-class position with no explicit tag is E1. A bare
# config-demanding function without the deferred wrapper is E8. Dual inclusion yields two
# contributions, one per producing position (§2.6.1).
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
    clsHm
    ;
  inherit (genPipe) channel contribute deferred;

  ch = channel { name = "c"; };
  tagOf = c: if c.class == null then null else c.class.id_hash;

  hostPos = {
    entity = host "axon-01";
    scope.host = host "axon-01";
    aspect = f.aspect "A";
    classes = [ clsNixos ];
  };
  userPos = {
    entity = user "sini";
    scope = {
      host = host "axon-01";
      user = user "sini";
    };
    aspect = f.aspect "A";
    classes = [ clsHm ];
  };

  # T2 — unique-class deferred contribution tags with the position's class.
  t2 = contribute {
    channel = ch;
    value = deferred ({ config }: config);
    producer = hostPos;
  };
  # T1 — explicit tag wins (even for plain data).
  t1 = contribute {
    channel = ch;
    value = [ "x" ];
    class = clsNixos;
    producer = hostPos;
  };
  # T3 — plain data, no explicit tag ⇒ neutral.
  t3 = contribute {
    channel = ch;
    value = [ "x" ];
    producer = hostPos;
  };
  # dual inclusion — same aspect at both positions.
  duH = contribute {
    channel = ch;
    value = deferred ({ config }: config);
    producer = hostPos;
  };
  duU = contribute {
    channel = ch;
    value = deferred ({ config, osConfig }: config);
    producer = userPos;
  };

  tri = builtins.tryEval;
in
{
  flake.tests.law-class-tagging = {
    test-t1-explicit = {
      expr = tagOf t1;
      expected = "cls:nixos";
    };
    test-t2-unique-class = {
      expr = tagOf t2;
      expected = "cls:nixos";
    };
    test-t3-neutral = {
      expr = tagOf t3;
      expected = null;
    };

    # dual inclusion: host position → nixos, user position → home-manager.
    test-dual-inclusion-host-tag = {
      expr = tagOf duH;
      expected = "cls:nixos";
    };
    test-dual-inclusion-user-tag = {
      expr = tagOf duU;
      expected = "cls:home-manager";
    };
    test-dual-inclusion-producers-differ = {
      expr = duH.producer.entity.id_hash != duU.producer.entity.id_hash;
      expected = true;
    };

    # T4 — deferred, 0 classes ⇒ E1.
    test-t4-zero-classes-e1 = {
      expr =
        (tri
          (contribute {
            channel = ch;
            value = deferred ({ config }: config);
            producer = hostPos // {
              classes = [ ];
            };
          }).class
        ).success;
      expected = false;
    };
    # T4 — deferred, ≥2 classes ⇒ E1.
    test-t4-two-classes-e1 = {
      expr =
        (tri
          (contribute {
            channel = ch;
            value = deferred ({ config }: config);
            producer = hostPos // {
              classes = [
                clsNixos
                clsHm
              ];
            };
          }).class
        ).success;
      expected = false;
    };
    # E7 — explicit tag not bound at the position.
    test-e7-tag-not-bound = {
      expr =
        (tri
          (contribute {
            channel = ch;
            value = [ "x" ];
            class = clsHm; # position only binds nixos
            producer = hostPos;
          }).class
        ).success;
      expected = false;
    };
    # E8 — bare config-demanding function without the deferred wrapper.
    test-e8-undeclared-deferral = {
      expr =
        (tri
          (contribute {
            channel = ch;
            value = { config }: config;
            producer = hostPos;
          }).class
        ).success;
      expected = false;
    };
  };
}
