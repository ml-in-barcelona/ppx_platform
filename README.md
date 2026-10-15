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

### match%platform

`match%platform` picks one of two expressions at compile time. The cases are
`Server` (native) and `Client` (Melange), also accepted as `Runtime.Server` and
`Runtime.Client`. In Reason, write `switch%platform`.

```ocaml
let storage =
  match%platform () with
  | Server -> In_memory.make ()
  | Client -> Local_storage.make ()
```

The ppx keeps only the branch for the current target, so each build compiles
different code:

```ocaml
(* native *)
let storage = In_memory.make ()
```

```ocaml
(* Melange *)
let storage = Local_storage.make ()
```

This lets one codebase:

1. Behave differently on each target where it must, for example store data in
   memory on the server and in `localStorage` in the browser.
2. Use modules that exist on one target only. In the example above,
   `Local_storage` does not exist on native. Native never compiles the `Client`
   branch, so the native build does not need it.

### [@platform js] / [@platform native]

For modules and other top-level items. The item stays on one target only:

```ocaml
include struct
  type t = Js.Json.t
end [@@platform js]

include struct
  type t = Yojson.Basic.t
end [@@platform native]
```

### browser_only

For functions and bindings that only work in the browser. `let%browser_only`
keeps the function on Melange. On native, the body raises
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

## Licence

MIT
