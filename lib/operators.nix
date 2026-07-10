# Operator algebra (§2.3, §2.3a). Deriving operators (map/filter/fold/scan/join) return channel
# VALUES that carry their defining edge in `__derive`; delivery operators (route/tee) return op
# VALUES that `compose` turns into inbound delivery edges (§2.1/L11). All operators are
# non-destructive reads of their inputs (L10). The sequence semantics live in evaluate.nix; this
# module only builds the DAG-node/edge records and pins derived-channel identity + attribute reset
# (L12).
{ prelude, channel }:
let
  inherit (prelude) head isFunction;
  inherit (channel) defaultCombine;

  # A derived channel: identity is the explicit record-form `name`, else the deterministic base
  # `"<inputName>.<op>"` (`"join"` for multi-input join); `compose` appends `.<declIndex>` for the
  # final, uniqueness-checked name (§2.3a). Attributes RESET to declaration defaults — merge/combine/
  # dedup/type/class are never inherited (L12); the record form may re-declare name/type/dedup/class,
  # while merge/combine stay at the ordered-list defaults (a different fold is a fold/join, not an
  # attribute).
  mkDerived =
    {
      op,
      inputs,
      rc ? { },
      derive,
    }:
    let
      name = rc.name or null;
      headId = (head inputs).id;
      base = if op == "join" then "join" else "${headId}.${op}";
    in
    {
      __genPipeChannel = true;
      __derived = true;
      inherit op name;
      id = if name != null then name else base;
      __derive = {
        inherit op inputs;
      }
      // derive;
      type = rc.type or null;
      merge = "ordered-list";
      combine = defaultCombine;
      init = [ ];
      dedup = rc.dedup or null;
      class = {
        expect = rc.class.expect or null;
        adapters = rc.class.adapters or [ ];
      };
    };

  # `arg` may be the bare function OR the record form carrying identity/attributes (§2.3a).
  asRec = key: arg: if isFunction arg then { ${key} = arg; } else arg;
in
{
  map =
    arg: ch:
    let
      r = asRec "f" arg;
    in
    mkDerived {
      op = "map";
      inputs = [ ch ];
      rc = r;
      derive = { inherit (r) f; };
    };

  filter =
    arg: ch:
    let
      r = asRec "p" arg;
    in
    mkDerived {
      op = "filter";
      inputs = [ ch ];
      rc = r;
      derive = { inherit (r) p; };
    };

  fold =
    r: ch:
    mkDerived {
      op = "fold";
      inputs = [ ch ];
      rc = r;
      derive = {
        inherit (r) f init;
      };
    };

  scan =
    r: ch:
    mkDerived {
      op = "scan";
      inputs = [ ch ];
      rc = r;
      derive = {
        inherit (r) f init;
      };
    };

  # `over f` applies `f` to the channel's WHOLE contribution-value list at once (`f : [a] -> [b]`),
  # re-seeding each element of the result as a fresh contribution (§2.3). map/filter/fold/scan are the
  # STRUCTURED list operators (Bird–Meertens `map`/catamorphism/`scan` — each carrying a fusion law and
  # a value-independent output shape); `over` is the UNSTRUCTURED general list function — the escape hatch
  # for whole-list rewrites (sort, take, reverse, cross-element rewrite) that no structured operator
  # expresses. It carries no fusion law and, because its OUTPUT CARDINALITY depends on the values, it is
  # value-demanding and strict where fold/scan stay lazy (see evaluate.nix `overC`). `arg` is the bare
  # `f` or the §2.3a record form (identity/attributes).
  over =
    arg: ch:
    let
      r = asRec "f" arg;
    in
    mkDerived {
      op = "over";
      inputs = [ ch ];
      rc = r;
      derive = { inherit (r) f; };
    };

  join =
    r:
    mkDerived {
      op = "join";
      inputs = r.inputs;
      rc = r;
      derive = {
        combine = r.combine or null;
      };
    };

  # Delivery operators — targets are EXISTING channels (declared or derived); they derive nothing.
  route =
    {
      from,
      select,
      to,
    }:
    {
      __genPipeOp = true;
      op = "route";
      inherit from select to;
    };

  # `route { from, select, to } ≡ tee { from; outputs = [ { inherit select to; } ]; }` — both kept
  # for vocabulary clarity (§2.3). tee returns the op record (compose expands one edge per output).
  tee =
    { from, outputs }:
    {
      __genPipeOp = true;
      op = "tee";
      inherit from outputs;
    };
}
