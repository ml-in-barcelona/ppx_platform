# Changes

## 0.1.0

Initial release, extracted from `browser_ppx` in
[server-reason-react](https://github.com/ml-in-barcelona/server-reason-react).

- Add `let%browser_only`, `%browser_only` expressions and the `[@browser_only]` attribute.
- Add `[@platform js]` and `[@platform native]` attributes.
- Add `switch%platform` with `Server`/`Client` and `Runtime.Server`/`Runtime.Client` patterns.
- Add the `-js` driver flag to preprocess for Melange.
- Add `ppx_platform.runtime`, with the `Ppx_platform_runtime` module that the generated code calls.
