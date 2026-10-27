# Changes

## Unreleased

- Breaking: remove the `-js` driver flag. The ppx now reads the ppxlib cookie `compilation-mode` that dune passes
  with `(lang dune 3.26)` or later: `"melange"` selects Melange, `"ocaml"` or no cookie selects native. Replace
  `(pps ppx_platform -- -js)` with `(pps ppx_platform)`. An unknown value is an error.
- Add the odoc documentation page `doc/index.mld`, moved from server-reason-react. It shows the package page on ocaml.org.
- Add `make docs` (`dune build @docs`). It writes `docs/index.md`. CI checks that it is current.

## 0.3.0

- Breaking: the runtime module `Ppx_platform_runtime` is now `Ppx_platform`. `exception Impossible_in_ssr of string` is
  now `exception Melange_only of string`, and `fail_impossible_action_in_ssr` is now `fail_melange_only`. It prints a
  hint and the call stack to stderr only when backtraces are on (`OCAMLRUNPARAM=b` or `Printexc.record_backtrace true`),
  then raises. The library name of the ppx is now `ppx_platform_ppx`. The public names `ppx_platform` and
  `ppx_platform.runtime` do not change.
- Breaking: remove the old names. Until 1.0.0, each one is an error that names its replacement, so a migration finds
  every leftover. Replace each one as follows:

  | Removed                                                                      | Use                                   |
  | ---------------------------------------------------------------------------- | ------------------------------------- |
  | `let%browser_only`, `[%browser_only ...]`, `[%%browser_only ...]`            | `let%melange_only`, `[%melange_only ...]`, `[%%melange_only ...]` |
  | `[@browser_only]`, `[@@browser_only]`, `[@platform js]`, `[@@platform js]`   | `[@melange_only]`, `[@@melange_only]` |
  | `[@platform native]`, `[@@platform native]`                                  | `[@native_only]`, `[@@native_only]`   |
  | `Server`, `Runtime.Server` in `match%platform` / `switch%platform`           | `Native`                              |
  | `Client`, `Runtime.Client` in `match%platform` / `switch%platform`           | `Melange`                             |

- Breaking: the `browser_only` alert is gone. Native code gets a `melange_only` alert with a new message: "This value only
  exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform."
- Error messages that said `[browser_ppx]` or `browser_only` now say `[ppx_platform]` and `melange_only`.

## 0.2.0

- Add `Native` and `Melange` cases to `match%platform` / `switch%platform`. `Server`, `Client`, `Runtime.Server` and
  `Runtime.Client` still work and can be mixed with the new cases.
- Add `[@melange_only]` / `[@@melange_only]`, `let%melange_only` and `[%melange_only ...]`, the new names of
  `[@browser_only]` / `[@platform js]` and `browser_only`. Native code gets a `melange_only` alert, not `browser_only`.
- Add `[@native_only]` / `[@@native_only]`, the new name of `[@platform native]`.
- The old names keep working in this release and will be removed in 1.0.0.

## 0.1.0

Initial release, extracted from `browser_ppx` in
[server-reason-react](https://github.com/ml-in-barcelona/server-reason-react).

- Add `let%browser_only`, `%browser_only` expressions and the `[@browser_only]` attribute.
- Add `[@platform js]` and `[@platform native]` attributes.
- Add `switch%platform` with `Server`/`Client` and `Runtime.Server`/`Runtime.Client` patterns.
- Add the `-js` driver flag to preprocess for Melange.
- Add `ppx_platform.runtime`, with the `Ppx_platform_runtime` module that the generated code calls.
