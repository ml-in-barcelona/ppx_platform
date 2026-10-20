
# ppx\_platform

`ppx_platform` keeps one codebase for native and [Melange](https://melange.re) builds. Some code only makes sense in the browser: it queries the DOM, or calls `Webapi`. The ppx removes that code from the native build and replaces it with a runtime failure. It can also pick different code for each target.

The page uses Reason syntax. The ppx works the same way in OCaml syntax. See the [README](https://github.com/ml-in-barcelona/ppx_platform#readme) for OCaml examples.


## Installation

Add `ppx_platform` to the `pps` field of each dune stanza (`library`, `executable` or `melange.emit`). Use it in both the native and the Melange stanzas. The Melange one needs the `-js` flag:

```ocaml
; native executable
(executable
 (name server)
 (preprocess
  (pps ppx_platform)))

; melange emitting JavaScript
(melange.emit
 (target app)
 (preprocess
  (pps ppx_platform -- -js)))
```
Without `ppx_platform` in `pps`, the compiler fails with `Uninterpreted extension 'melange_only'` on any `[%melange_only]` you write.


## Usage


### `let%melange_only`: discard functions on native

```ocaml
let%melange_only countDomNodes = (id) => {
  let elements = Webapi.Element.querySelector("#" ++ id);
  let arr_elements = Webapi.Element.toArray(elements);
  Array.length(arr_elements);
};
```
The Melange build keeps the function. In the native build, the ppx replaces the body with a call that raises `Ppx_platform.Melange_only`. The binding also gets a `melange_only` alert. Native code that calls it outside another `let%melange_only` gets this alert, which is an error with `-alert @melange_only`.

If the function runs on native anyway, it raises the exception. When backtraces are on (`OCAMLRUNPARAM=b` or `Printexc.record_backtrace true`), it first prints a hint and the call stack to stderr. An uncaught exception stops the program, so catch it if you are not sure that the function stays away from native. You can also catch it to give a fallback value:

```ocaml
let main = id =>
  switch (countDomNodes(id)) {
  | exception Ppx_platform.Melange_only(_name) => 0
  | count => count
  };
```
`main` returns `0` on native, because `countDomNodes` raises. The call in `main` still triggers the `melange_only` alert. Silence it on the identifier with `[@alert "-melange_only"]`.

`[%melange_only fun ...]` does the same for a single function expression:

```ocaml
let on_click = [%melange_only (event) => Js.log(event)];
```

### `switch%platform`: pick an expression per target

The cases are `Native` and `Melange`:

```ocaml
switch%platform () {
| Native => print_endline("This prints to the terminal")
| Melange => Js.log("This prints to the console")
};
```
Any expression can be part of the switch:

```ocaml
let howManyColumns =
  switch%platform () {
  | Native => 0
  | Melange => 12
  };
```
The ppx keeps only the branch for the current target. Both branches must have the same type.


### `[@melange_only]` and `[@native_only]`: pick items per target

These attributes apply to modules, types, `open`, `include` and other top-level items. They also apply to record fields and variant constructors. The ppx drops an item when its attribute names the other target:

```ocaml
[@melange_only]
module X = {
  type t = Js.Json.t;
  let a = 2 + 2;
};

[@native_only]
module Y = {
  type t = Yojson.Basic.t;
  let a = 4 + 4;
};
```
The Melange build keeps `X`, and the native build keeps `Y`.

If two items have the same name, each build keeps one of them. The module then exists on both targets:

```ocaml
[@melange_only]
module X = {
  type t = Js.Json.t;
};

[@native_only]
module X = {
  type t = Yojson.Basic.t;
};
```

## Libraries

The ppx is the `ppx_platform` library. The generated code calls the runtime library `ppx_platform.runtime`.
