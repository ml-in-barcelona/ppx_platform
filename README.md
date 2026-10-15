# ppx_platform

A ppx rewriter that keeps one OCaml codebase for native and
[Melange](https://melange.re) builds. It picks the code that each target
compiles and replaces browser-only code with a runtime failure on native.

Extracted from
[server-reason-react](https://github.com/ml-in-barcelona/server-reason-react).

## Install

```sh
opam install ppx_platform
```

## Setup

Native library or executable:

```dune
(library
 (name my_lib)
 (preprocess
  (pps ppx_platform)))
```

Melange library: pass the `-js` flag to the ppx.

```dune
(library
 (name my_lib_js)
 (modes melange)
 (preprocess
  (pps ppx_platform -- -js)))
```

The ppx adds `ppx_platform.runtime` as a dependency of both builds.

## Syntax

`let%browser_only` keeps the function on Melange. On native, the body becomes a
call to `Ppx_platform_runtime.fail_impossible_action_in_ssr`, which raises
`Ppx_platform_runtime.Impossible_in_ssr`:

```ocaml
let%browser_only focus_input element = Webapi.Dom.HtmlElement.focus element
```

`[%browser_only fun ...]` does the same for an expression:

```ocaml
let on_click = [%browser_only fun event -> Js.log event]
```

`[@browser_only]` removes an item or a record field on native:

```ocaml
let window_size = (fun () -> (0, 0)) [@@browser_only]
```

`[@platform js]` and `[@platform native]` keep an item on one target only:

```ocaml
include struct
  type t = Js.Json.t
end [@@platform js]

include struct
  type t = Yojson.Basic.t
end [@@platform native]
```

`switch%platform` picks one of two expressions at compile time. The cases are
`Server` (native) and `Client` (Melange), also accepted as `Runtime.Server` and
`Runtime.Client`:

```ocaml
let storage =
  match%platform () with
  | Server -> In_memory.make ()
  | Client -> Local_storage.make ()
```

## Licence

MIT
