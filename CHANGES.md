# Changes

## Unreleased

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
