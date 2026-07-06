# Channel declaration (§2.1 / §4.1) and discipline validation (E10/E10b). A channel is declared once
# and instantiated per scope position at run time; its value at a position is the left fold of its
# pinned, deduped contribution sequence under the associative-only combine (L1).
{ prelude, errors }:
let
  # Discipline validation fires primarily here (channel construction) and is re-validated by compose
  # for hand-built records — same golden message at both firing points (§2.5 item 3).
  validateMerge =
    name: merge:
    if merge == "ordered-list" then
      merge
    else if merge == "semilattice-set" then
      throw (
        errors.e10 {
          channel = name;
          inherit merge;
        }
      )
    else
      throw (
        errors.e10b {
          channel = name;
          inherit merge;
        }
      );

  # Default combine + init: the associative-only left fold whose default is ordered list
  # concatenation, so the default channel value is the ordered contribution list (§2.1). `init` is
  # the fold seed (§2.1 writes `foldl combine init …`); it is an argument-shape refinement of the API
  # sketch, unavoidable so an empty channel folds to `init` rather than erroring.
  defaultCombine = a: b: a ++ b;
in
{
  inherit validateMerge defaultCombine;

  channel =
    {
      name,
      type ? null,
      merge ? "ordered-list",
      combine ? defaultCombine,
      init ? [ ],
      dedup ? null,
      class ? { },
    }:
    {
      __genPipeChannel = true;
      __derived = false;
      id = name; # a declared channel's identity IS its name
      inherit
        name
        type
        combine
        init
        dedup
        ;
      merge = validateMerge name merge;
      class = {
        expect = class.expect or null;
        adapters = class.adapters or [ ];
      };
    };
}
