# Shared stub fixtures for the gen-pipe suites. Hand-built position/order/class tables keep the
# suites pure and gen-scope-independent (§7); one integration group runs against real gen-scope.
{ genPipe }:
let
  inherit (genPipe) contribute deferred;
in
rec {
  # ── stub registry entries (opaque id_hash-bearing values) ──
  ent = kind: name: {
    id_hash = "h:${kind}:${name}";
    inherit name kind;
  };
  host = ent "host";
  user = ent "user";
  aspect = ent "aspect";

  # ── stub class registry entries ──
  clsNixos = {
    id_hash = "cls:nixos";
    name = "nixos";
  };
  clsHm = {
    id_hash = "cls:home-manager";
    name = "home-manager";
  };

  # ── producing positions (dual-inclusion of §2.6.1) ──
  # host position → binds nixos; user position → binds home-manager.
  hostProducer =
    {
      h,
      aspect ? "asp",
      classes ? [ clsNixos ],
    }:
    {
      entity = host h;
      scope = {
        host = host h;
      };
      aspect = ent "aspect" aspect;
      inherit classes;
    };
  userProducer =
    {
      h,
      u,
      aspect ? "asp",
      classes ? [ clsHm ],
    }:
    {
      entity = user u;
      scope = {
        host = host h;
        user = user u;
      };
      aspect = ent "aspect" aspect;
      inherit classes;
    };

  # A contribution at a host position (default nixos, class-neutral unless value is deferred).
  contribHost =
    {
      channel,
      value,
      h ? "axon-01",
      aspect ? "asp",
      class ? null,
      classes ? [ clsNixos ],
    }:
    contribute {
      inherit channel value class;
      producer = hostProducer { inherit h aspect classes; };
    };

  contribUser =
    {
      channel,
      value,
      h ? "axon-01",
      u ? "sini",
      aspect ? "asp",
      class ? null,
      classes ? [ clsHm ],
    }:
    contribute {
      inherit channel value class;
      producer = userProducer {
        inherit
          h
          u
          aspect
          classes
          ;
      };
    };

  # ── traversal adapter builder ──
  # `table` : position -> channelName -> [ contribution ].  Single-position by default.
  mkTraversal =
    {
      table ? { },
      order ? (p: [ p ]),
      classesOf ? (_: [ ]),
      resolveDeferred ? null,
      render ? (c: builtins.toJSON c),
    }:
    {
      inherit order classesOf render;
      contributionsAt = p: chName: (table.${p} or { }).${chName} or [ ];
    }
    // (if resolveDeferred == null then { } else { inherit resolveDeferred; });

  inherit deferred;
}
