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
let api_url path =
  match%platform () with
  | Server -> Sys.getenv "API_URL" ^ path
  | Client -> path

let now_ms () =
  match%platform () with
  | Server -> Unix.gettimeofday () *. 1000.
  | Client -> Js.Date.now ()
```

The ppx keeps only the branch for the current target, so each build compiles
different code:

```ocaml
(* native *)
let api_url path = Sys.getenv "API_URL" ^ path
let now_ms () = Unix.gettimeofday () *. 1000.
```

```ocaml
(* Melange *)
let api_url path = path
let now_ms () = Js.Date.now ()
```

This lets one codebase:

1. Behave differently on each target where it must. In `api_url`, the server
   needs an absolute URL, and the browser can use a relative one.
2. Use modules that exist on one target only. In `now_ms`, `Unix` does not
   exist in Melange and `Js.Date` does not exist on native. Each build compiles
   only its own branch, so neither needs the other's module.

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

For functions and let bindings that only get compiled by Melange and are meant
for the browser. On native, the body becomes an expression that raises
`Ppx_platform_runtime.Impossible_in_ssr`, and the binding gets a
`browser_only` alert. So native code that calls it outside another
`let%browser_only` gets a compiler alert (an error with
`-alert @browser_only`):

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
