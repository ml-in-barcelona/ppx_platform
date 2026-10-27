Native / Melange cases, melange_only and native_only.

match%platform accepts Native and Melange

  $ cat > switch.ml << EOF
  > let a = match%platform () with Native -> "native" | Melange -> "melange"
  > let b = match%platform () with Melange -> "melange" | Native -> "native"
  > EOF

  $ ./standalone.exe -impl switch.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let a = "melange"
  let b = "melange"

  $ ./standalone.exe -impl switch.ml | ocamlformat - --enable-outside-detected-project --impl
  let a = "native"
  let b = "native"

Wrong case names or count are errors

  $ cat > switch_error.ml << EOF
  > let a = match%platform () with Native -> 1 | Native -> 2
  > let b = match%platform () with Native -> 1 | Other -> 2
  > let c = match%platform () with Native -> 1
  > EOF

  $ ./standalone.exe -impl switch_error.ml | ocamlformat - --enable-outside-detected-project --impl
  let a =
    [%ocaml.error
      "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange`"]
  
  let b =
    [%ocaml.error
      "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange`"]
  
  let c =
    [%ocaml.error "[ppx_platform] switch%platform requires a match expression"]

Attributes on items, fields and types

  $ cat > attrs.ml << EOF
  > include struct type t = Js.Json.t end [@@melange_only]
  > include struct type t = Yojson.Basic.t end [@@native_only]
  > module M = struct let x = 1 end [@@melange_only]
  > module N = struct let x = 2 end [@@native_only]
  > type r = { always : int; js : int [@melange_only]; nat : int [@native_only] }
  > type v = A | B [@melange_only] | C [@native_only]
  > let melange = (fun () -> 1) [@@melange_only]
  > let native = (fun () -> 2) [@@native_only]
  > external e : int -> int = "e" [@@melange_only]
  > EOF

  $ ./standalone.exe -impl attrs.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Js.Json.t
  end [@@melange_only]
  
  module M = struct
    let x = 1
  end
  [@@melange_only]
  
  type r = { always : int; js : int [@melange_only] }
  type v = A | B [@melange_only]
  
  let melange () = 1 [@@melange_only]
  
  external e : int -> int = "e" [@@melange_only]

  $ ./standalone.exe -impl attrs.ml | ocamlformat - --enable-outside-detected-project --impl
  include struct
    type t = Yojson.Basic.t
  end [@@native_only]
  
  module N = struct
    let x = 2
  end
  [@@native_only]
  
  type r = { always : int; nat : int [@native_only] }
  type v = A | C [@native_only]
  
  let native () = 2 [@@native_only]

  $ cat > attrs.mli << EOF
  > val a : int [@@melange_only]
  > val b : int [@@native_only]
  > type t = { x : int [@melange_only]; y : int [@native_only] }
  > EOF

  $ ./standalone.exe -intf attrs.mli -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --intf
  val a : int [@@melange_only]
  
  type t = { x : int [@melange_only] }

  $ ./standalone.exe -intf attrs.mli | ocamlformat - --enable-outside-detected-project --intf
  val b : int [@@native_only]
  
  type t = { y : int [@native_only] }

On expressions, the attribute of the target that drops it is an error

  $ cat > attr_expr.ml << EOF
  > let a = (1 [@melange_only])
  > let b = (1 [@native_only])
  > EOF

  $ ./standalone.exe -impl attr_expr.ml | ocamlformat - --enable-outside-detected-project --impl
  let a =
    [%ocaml.error
      "Don't use melange_only on expressions, use switch%platform instead"]
  
  let b = (1 [@native_only])

  $ ./standalone.exe -impl attr_expr.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let a = (1 [@melange_only])
  
  let b =
    [%ocaml.error
      "Don't use native_only on expressions, use switch%platform instead"]

let%melange_only and [%melange_only ...]

  $ cat > ext.ml << EOF
  > let%melange_only f (x : int) = x + 1
  > let%melange_only g ?(a = 1) b = a + b
  > let%melange_only h = Webapi.Dom.getElementById
  > let on_click = [%melange_only fun event -> Js.log event]
  > let not_a_function = [%melange_only 1]
  > [%%melange_only let ( let+ ) = fun p f -> map f p]
  > EOF

  $ ./standalone.exe -impl ext.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let f (x : int) = x + 1
  let g ?(a = 1) b = a + b
  let h = Webapi.Dom.getElementById
  let on_click event = Js.log event
  let not_a_function = 1
  let ( let+ ) p f = map f p

  $ ./standalone.exe -impl ext.ml | ocamlformat - --enable-outside-detected-project --impl
  let (f
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun x -> Ppx_platform.fail_melange_only "f") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (g
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ?a -> Ppx_platform.fail_melange_only "g") [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (h
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
    Obj.magic () [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let on_click event = Ppx_platform.fail_melange_only "event"
  
  let not_a_function =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  
  let (( let+ )
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun p -> Ppx_platform.fail_melange_only "let+") [@alert "-melange_only"]
  [@@warning "-27-32"]

A floating attribute at the start of a file drops the whole file

  $ cat > floating.ml << EOF
  > [@@@melange_only]
  > let x = 1
  > EOF

  $ ./standalone.exe -impl floating.ml | ocamlformat - --enable-outside-detected-project --impl

  $ ./standalone.exe -impl floating.ml -cookie 'compilation-mode="melange"' | ocamlformat - --enable-outside-detected-project --impl
  let x = 1

The -melange flag is not registered: server-reason-react.ppx registers it, and
ppxlib runs only one handler for a duplicated flag.

  $ ./standalone.exe -impl mixed.ml -melange 2>&1 | head -2
  ./standalone.exe: unknown option '-melange'.
  standalone.exe [extra_args] [<files>]

Removed names are errors that name the replacement. The first one stops the
preprocessing of an attribute.

  $ cat > removed_switch.ml << EOF
  > let a = match%platform () with Server -> 1 | Melange -> 2
  > let b = match%platform () with Native -> 1 | Client -> 2
  > let c = match%platform () with Runtime.Server -> 1 | Runtime.Client -> 2
  > EOF

  $ ./standalone.exe -impl removed_switch.ml | ocamlformat - --enable-outside-detected-project --impl
  let a =
    [%ocaml.error "[ppx_platform] `Server` was removed in 0.3.0, use `Native`"]
  
  let b =
    [%ocaml.error "[ppx_platform] `Client` was removed in 0.3.0, use `Melange`"]
  
  let c =
    [%ocaml.error "[ppx_platform] `Server` was removed in 0.3.0, use `Native`"]

  $ cat > removed_ext.ml << EOF
  > let%browser_only f x = x
  > let g = [%browser_only fun x -> x]
  > [%%browser_only let h x = x]
  > EOF

  $ ./standalone.exe -impl removed_ext.ml | ocamlformat - --enable-outside-detected-project --impl
  [%%ocaml.error
  "[ppx_platform] %browser_only was removed in 0.3.0, use %melange_only"]
  
  let g =
    [%ocaml.error
      "[ppx_platform] %browser_only was removed in 0.3.0, use %melange_only"]
  
  [%%ocaml.error
  "[ppx_platform] %browser_only was removed in 0.3.0, use %melange_only"]

  $ for attr in "@@browser_only" "@@platform js" "@@platform native" "@@platform other"; do
  >   echo "let x = 1 [$attr]" > removed_attr.ml
  >   ./standalone.exe -impl removed_attr.ml
  > done
  File "removed_attr.ml", line 1, characters 10-26:
  1 | let x = 1 [@@browser_only]
                ^^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@browser_only] was removed in 0.3.0, use [@melange_only]
  File "removed_attr.ml", line 1, characters 10-25:
  1 | let x = 1 [@@platform js]
                ^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform js] was removed in 0.3.0, use [@melange_only]
  File "removed_attr.ml", line 1, characters 10-29:
  1 | let x = 1 [@@platform native]
                ^^^^^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform native] was removed in 0.3.0, use [@native_only]
  File "removed_attr.ml", line 1, characters 10-28:
  1 | let x = 1 [@@platform other]
                ^^^^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform ...] was removed in 0.3.0, use [@melange_only] or [@native_only]
  [1]

  $ for attr in "@browser_only" "@platform js"; do
  >   echo "let x = (1 [$attr])" > removed_attr.ml
  >   ./standalone.exe -impl removed_attr.ml
  > done
  File "removed_attr.ml", line 1, characters 11-26:
  1 | let x = (1 [@browser_only])
                 ^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@browser_only] was removed in 0.3.0, use [@melange_only]
  File "removed_attr.ml", line 1, characters 11-25:
  1 | let x = (1 [@platform js])
                 ^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform js] was removed in 0.3.0, use [@melange_only]
  [1]

  $ echo "type t = { a : int [@platform js] }" > removed_field.ml
  $ ./standalone.exe -impl removed_field.ml
  File "removed_field.ml", line 1, characters 19-33:
  1 | type t = { a : int [@platform js] }
                         ^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform js] was removed in 0.3.0, use [@melange_only]
  [1]

  $ echo "[@@@browser_only]" > removed_floating.ml
  $ ./standalone.exe -impl removed_floating.ml
  File "removed_floating.ml", line 1, characters 0-17:
  1 | [@@@browser_only]
      ^^^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@browser_only] was removed in 0.3.0, use [@melange_only]
  [1]

  $ echo "val x : int [@@platform native]" > removed.mli
  $ ./standalone.exe -intf removed.mli
  File "removed.mli", line 1, characters 12-31:
  1 | val x : int [@@platform native]
                  ^^^^^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform native] was removed in 0.3.0, use [@native_only]
  [1]

  $ echo "let x = 1 [@@platform js]" > removed_attr.ml
  $ ./standalone.exe -impl removed_attr.ml -cookie 'compilation-mode="melange"'
  File "removed_attr.ml", line 1, characters 10-25:
  1 | let x = 1 [@@platform js]
                ^^^^^^^^^^^^^^^
  Error: [ppx_platform] [@platform js] was removed in 0.3.0, use [@melange_only]
  [1]
