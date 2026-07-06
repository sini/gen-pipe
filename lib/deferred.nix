# Explicit deferral (§2.6.3). `deferred fn` marks a value as config-demanding; `fn` is a function of
# an attrset whose functionArgs may demand `config`, the producing class's registered parent-config
# argument (e.g. `osConfig`), scope-context bindings, and `lib`. Until resolution the contribution's
# `value` field is a poisoned thunk throwing E6, so any value-demanding operator or consumer that
# forces it produces the precise error with no separate detection pass.
{ prelude, errors }:
let
  inherit (prelude) isAttrs;
in
{
  deferred = fn: {
    __genPipeDeferred = true;
    inherit fn;
  };

  isDeferred = v: isAttrs v && (v.__genPipeDeferred or false);

  # A value that throws E6 when forced. Metadata access (producer/class/deferred/provenance/channel)
  # never touches it; only a value-demanding fold/scan/join-combine/consumer or a selector that
  # reaches for `.value` forces the throw. The `op` is generic here ("value-access"); value-demanding
  # operators (fold/scan/join-with-combine) pre-check and raise a same-content E6 naming themselves.
  poison =
    { channel, producer }:
    throw (
      errors.e6 {
        inherit channel producer;
        op = "value-access";
      }
    );
}
