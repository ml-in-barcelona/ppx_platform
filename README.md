# ppx_platform

A ppx rewriter that keeps one OCaml codebase for native and
[Melange](https://melange.re) builds. It picks the code that each target
compiles and replaces Melange-only code with a runtime failure on native.

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

Melange library needs the `-js` flag to the ppx.

```dune
(library
 (name my_lib_js)
 (modes melange)
 (preprocess
  (pps ppx_platform -- -js)))
```

## Syntax

### `match%platform`

`match%platform` picks one of two expressions at compile time. The cases are
`Native` and `Melange`:

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

1. Behave differently on each target where it must. In `api`, the server needs an absolute URL, and the browser can use a relative one.
2. Use modules that exist on one target only. In `now`, `Unix` does not exist in Melange and `Js.Date` does not exist on native. Each build compiles only its own branch, so neither needs the other's module.

### `[@melange_only]` / `[@native_only]`

For modules and other top-level items:

```ocaml
include [@melange_only] struct
  type t = Js.Json.t
end

include [@native_only] struct
  type t = Yojson.Basic.t
end
```

Two items with the same name are fine. Each build keeps only one of them, so
the module exists on both targets:

```ocaml
module [@melange_only] X = struct
  type t = Js.Json.t
end

module [@native_only] X = struct
  type t = Yojson.Basic.t
end
```

On an `external` with a function type, the native build defines a function of
that type that raises `Ppx_platform.Melange_only`, so the external can stand
behind an interface. It keeps the labels and gets no alert. The native build
removes an external of any other type.

```ocaml
external set_attribute : Dom.element -> string -> string -> unit = "setAttribute"
[@@mel.send] [@@melange_only]
```

### `let%melange_only`

For functions and let bindings that only get compiled by Melange and are meant
for the browser.

```ocaml
let%melange_only focus_input element = Webapi.Dom.HtmlElement.focus element
```

On native, the body becomes an expression that raises `Ppx_platform.Melange_only`, and the binding gets a `melange_only` alert. So native code that calls it outside another
`let%melange_only` gets a compiler alert (an error with `-alert @melange_only`):

To have a fallback value instead, catch the exception:

```ocaml
let%melange_only window_width () = Webapi.Dom.(window |> Window.innerWidth)

let width () =
  try window_width () with Ppx_platform.Melange_only _ -> 0
```

With a function type as annotation, the native build defines the value from
the type, whatever the body is. So a `[%mel.raw]` value works too, and the
value keeps its type and labels to match an interface:

```ocaml
let%melange_only set_title : string -> unit = [%mel.raw "function (t) { document.title = t }"]
```

`[%melange_only fun ...]` does the same for an expression:

```ocaml
let on_click = [%melange_only fun event -> Js.log event]
```

## Licence

MIT

## Credits
Extracted from [server-reason-react](https://github.com/ml-in-barcelona/server-reason-react).
