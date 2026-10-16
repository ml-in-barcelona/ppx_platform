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
`Native` and `Melange`. In Reason, write `switch%platform`.

```ocaml
let api path =
  match%platform () with
  | Native -> Sys.getenv "API_URL" ^ path
  | Melange -> path

let now () =
  match%platform () with
  | Native -> Unix.gettimeofday () *. 1000.
  | Melange -> Js.Date.now ()
```

The ppx keeps only the branch for the current target, so each build compiles
different code:

```ocaml
(* native *)
let api path = Sys.getenv "API_URL" ^ path
let now () = Unix.gettimeofday () *. 1000.
```

```ocaml
(* Melange *)
let api path = path
let now () = Js.Date.now ()
```

Both branches must have the same type, because the type checker sees only the
one that remains for each target.

This lets one codebase:

1. Behave differently on each target where it must. In `api`, the server
   needs an absolute URL, and the browser can use a relative one.
2. Use modules that exist on one target only. In `now`, `Unix` does not
   exist in Melange and `Js.Date` does not exist on native. Each build compiles
   only its own branch, so neither needs the other's module.

### [@melange_only] / [@native_only]

For modules and other top-level items. The item stays on one target only:

```ocaml
include struct
  type t = Js.Json.t
end [@@melange_only]

include struct
  type t = Yojson.Basic.t
end [@@native_only]
```

Two items with the same name are fine. Each build keeps only one of them, so
the module exists on both targets:

```ocaml
module X = struct
  type t = Js.Json.t
end [@@melange_only]

module X = struct
  type t = Yojson.Basic.t
end [@@native_only]
```

### melange_only

For functions and let bindings that only get compiled by Melange and are meant
for the browser. On native, the body becomes an expression that raises
`Ppx_platform_runtime.Impossible_in_ssr`, and the binding gets a
`melange_only` alert. So native code that calls it outside another
`let%melange_only` gets a compiler alert (an error with
`-alert @melange_only`):

```ocaml
let%melange_only focus_input element = Webapi.Dom.HtmlElement.focus element
```

If native code calls it anyway, the exception is not caught and the program
crashes. To give a fallback value instead, catch the exception:

```ocaml
let%melange_only window_width () = Webapi.Dom.(window |> Window.innerWidth)

let width () =
  try window_width () with Ppx_platform_runtime.Impossible_in_ssr _ -> 0
```

`[%melange_only fun ...]` does the same for an expression:

```ocaml
let on_click = [%melange_only fun event -> Js.log event]
```

`[@melange_only]` removes an item or a record field on native:

```ocaml
let window_size = (fun () -> (0, 0)) [@@melange_only]
```

## Old names

The old names keep working and behave the same. They will be removed in
1.0.0. You can mix old and new names in one file, and in `match%platform` you
can mix `Native` with `Client` or `Melange` with `Server`.

| Old | New |
| --- | --- |
| `Server` / `Client` (also `Runtime.Server` / `Runtime.Client`) | `Native` / `Melange` |
| `[@platform js]`, `[@browser_only]` | `[@melange_only]` |
| `[@platform native]` | `[@native_only]` |
| `let%browser_only`, `[%browser_only ...]` | `let%melange_only`, `[%melange_only ...]` |

The generated alert has the name you used: `browser_only` for the old names and
`melange_only` for the new ones. Suppress it with `[@alert "-browser_only"]` or
`[@alert "-melange_only"]` to match.

The `-js` flag has no new name. `server-reason-react.ppx` already registers
`-melange`, and ppxlib runs only one handler when two ppxes register the same
flag.

## Licence

MIT
