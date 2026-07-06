# golden-errors (all). Every E1–E11 message asserts the pinned content fields of §2.8. The exact
# prose may evolve; the NAMED content is contract. Messages are the only place identities render as
# strings. Tested directly against the errors module (the throw SITES are exercised by the law
# suites; this suite pins the CONTENT).
{
  lib,
  genPrelude,
  ...
}:
let
  prelude = genPrelude;
  helpers = import ../../lib/helpers.nix { inherit prelude; };
  errors = import ../../lib/errors.nix { inherit prelude helpers; };

  ent = kind: name: {
    id_hash = "h:${kind}:${name}";
    inherit name kind;
  };
  clsNixos = {
    id_hash = "cls:nixos";
    name = "nixos";
  };
  clsHm = {
    id_hash = "cls:home-manager";
    name = "home-manager";
  };
  producer = {
    entity = ent "user" "sini";
    scope = {
      host = ent "host" "axon-01";
      user = ent "user" "sini";
    };
    aspect = ent "aspect" "derived-addrs";
  };
  has = sub: msg: lib.hasInfix sub msg;
  # every message names the channel; most name the producing aspect + entity + rendered scope.
  namesProducer = msg: has "derived-addrs" msg && has "sini" msg && has "axon-01" msg;

  m = {
    e1 = errors.e1 {
      channel = "http-backends";
      inherit producer;
      classes = [
        clsHm
        clsNixos
      ];
    };
    e2 = errors.e2 {
      channel = "http-backends";
      consumingClass = clsNixos;
      tag = clsHm;
      inherit producer;
    };
    e2b = errors.e2b {
      channel = "http-backends";
      from = clsHm;
      to = clsNixos;
    };
    e2c = errors.e2c {
      channel = "http-backends";
      tag = clsHm;
      inherit producer;
    };
    e3 = errors.e3 {
      cycle = [
        "a"
        "b"
        "a"
      ];
      ops = [
        "join"
        "route"
      ];
    };
    e4a = errors.e4a {
      op = "route";
      name = "missing";
    };
    e4b = errors.e4b { name = "dup"; };
    e5 = errors.e5 {
      channel = "http-backends";
      key = "K";
      kept = producer;
      dropped = producer;
    };
    e6 = errors.e6 {
      channel = "http-backends";
      op = "fold";
      inherit producer;
    };
    e7 = errors.e7 {
      channel = "http-backends";
      tag = clsHm;
      classes = [ clsNixos ];
      inherit producer;
    };
    e8 = errors.e8 {
      channel = "http-backends";
      inherit producer;
      demanded = [
        "config"
        "osConfig"
      ];
    };
    e9 = errors.e9 {
      channel = "http-backends";
      description = "must be a list";
      inherit producer;
    };
    e10 = errors.e10 {
      channel = "http-backends";
      merge = "semilattice-set";
    };
    e10b = errors.e10b {
      channel = "http-backends";
      merge = "bogus";
    };
    e11 = errors.e11 {
      channel = "http-backends";
      inherit producer;
    };
  };
in
{
  flake.tests.golden-errors = {
    # E1 — channel, aspect, entity, scope, the candidate class list, and both remedies.
    test-e1 = {
      expr = [
        (has "http-backends" m.e1)
        (namesProducer m.e1)
        (has "nixos" m.e1 && has "home-manager" m.e1)
        (has "class = " m.e1 && has "class-neutral" m.e1)
      ];
      expected = [
        true
        true
        true
        true
      ];
    };
    # E2 — channel, consuming class, contribution tag, producer, remedy.
    test-e2 = {
      expr = [
        (has "http-backends" m.e2)
        (has "nixos" m.e2 && has "home-manager" m.e2)
        (namesProducer m.e2)
        (has "adapters" m.e2)
      ];
      expected = [
        true
        true
        true
        true
      ];
    };
    # E2b — channel + the duplicated (from,to) pair.
    test-e2b = {
      expr = has "home-manager" m.e2b && has "nixos" m.e2b && has "http-backends" m.e2b;
      expected = true;
    };
    # E2c — channel, tag, producer, no-class note.
    test-e2c = {
      expr = has "home-manager" m.e2c && namesProducer m.e2c && has "no class" m.e2c;
      expected = true;
    };
    # E3 — the channel cycle in order + the operators forming each edge.
    test-e3 = {
      expr = has "a -> b -> a" m.e3 && has "join" m.e3 && has "route" m.e3;
      expected = true;
    };
    # E4a — referencing operator kind + missing channel name.
    test-e4a = {
      expr = has "route" m.e4a && has "missing" m.e4a;
      expected = true;
    };
    # E4b — the duplicate name.
    test-e4b = {
      expr = has "dup" m.e4b;
      expected = true;
    };
    # E5 — channel, identity key, BOTH producers.
    test-e5 = {
      expr = has "http-backends" m.e5 && has "K" m.e5 && has "kept" m.e5 && has "dropped" m.e5;
      expected = true;
    };
    # E6 — channel, accessing operator, producer, the deferred note.
    test-e6 = {
      expr = has "http-backends" m.e6 && has "fold" m.e6 && namesProducer m.e6 && has "resolve" m.e6;
      expected = true;
    };
    # E7 — channel, explicit class, position's actual class list, producer.
    test-e7 = {
      expr = has "home-manager" m.e7 && has "nixos" m.e7 && namesProducer m.e7;
      expected = true;
    };
    # E8 — channel, producer, the demanded config-like args, remedy.
    test-e8 = {
      expr =
        has "config" m.e8 && has "osConfig" m.e8 && has "genPipe.deferred" m.e8 && namesProducer m.e8;
      expected = true;
    };
    # E9 — channel, the type's description, producer.
    test-e9 = {
      expr = has "http-backends" m.e9 && has "must be a list" m.e9 && namesProducer m.e9;
      expected = true;
    };
    # E10 / E10b — channel, discipline, the reservation note (E10).
    test-e10 = {
      expr = has "semilattice-set" m.e10 && has "reserved" m.e10 && has "http-backends" m.e10;
      expected = true;
    };
    test-e10b = {
      expr = has "bogus" m.e10b && has "unknown" m.e10b;
      expected = true;
    };
    # E11 — channel, producer, both remedies (resolveDeferred / mode = records).
    test-e11 = {
      expr =
        has "http-backends" m.e11
        && namesProducer m.e11
        && has "resolveDeferred" m.e11
        && has "records" m.e11;
      expected = true;
    };
  };
}
