New names: Native / Melange cases, melange_only and native_only.

match%platform accepts Native and Melange

  $ cat > switch.ml << EOF
  > let a = match%platform () with Native -> "native" | Melange -> "melange"
  > let b = match%platform () with Melange -> "melange" | Native -> "native"
  > let c = match%platform () with Runtime.Server -> "native" | Runtime.Client -> "melange"
  > let d = match%platform () with Native -> "native" | Client -> "melange"
  > let e = match%platform () with Melange -> "melange" | Server -> "native"
  > let f = match%platform () with Server -> "native" | Melange -> "melange"
  > EOF

  $ ./standalone.exe -impl switch.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let a = "melange"
  let b = "melange"
  let c = "melange"
  let d = "melange"
  let e = "melange"
  let f = "melange"

  $ ./standalone.exe -impl switch.ml | ocamlformat - --enable-outside-detected-project --impl
  let a = "native"
  let b = "native"
  let c = "native"
  let d = "native"
  let e = "native"
  let f = "native"

Wrong case names or count are errors that mention the new names

  $ cat > switch_error.ml << EOF
  > let a = match%platform () with Native -> 1 | Native -> 2
  > let b = match%platform () with Native -> 1 | Other -> 2
  > let c = match%platform () with Native -> 1
  > EOF

  $ ./standalone.exe -impl switch_error.ml | ocamlformat - --enable-outside-detected-project --impl
  let a =
    [%ocaml.error
      "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange` \
       (the old names `Server` and `Client` also work)"]
  
  let b =
    [%ocaml.error
      "[ppx_platform] switch%platform requires 2 cases: `Native` and `Melange` \
       (the old names `Server` and `Client` also work)"]
  
  let c =
    [%ocaml.error "[browser_ppx] switch%platform requires a match expression"]

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

  $ ./standalone.exe -impl attrs.ml -js | ocamlformat - --enable-outside-detected-project --impl
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

  $ ./standalone.exe -intf attrs.mli -js | ocamlformat - --enable-outside-detected-project --intf
  val a : int [@@melange_only]
  
  type t = { x : int [@melange_only] }

  $ ./standalone.exe -intf attrs.mli | ocamlformat - --enable-outside-detected-project --intf
  val b : int [@@native_only]
  
  type t = { y : int [@native_only] }

On expressions, the attribute of the target that drops it is an error

  $ cat > attr_expr.ml << EOF
  > let a = (1 [@melange_only])
  > let b = (1 [@native_only])
  > let c = (1 [@browser_only])
  > EOF

  $ ./standalone.exe -impl attr_expr.ml | ocamlformat - --enable-outside-detected-project --impl
  let a =
    [%ocaml.error
      "Don't use melange_only on expressions, use switch%platform instead"]
  
  let b = (1 [@native_only])
  
  let c =
    [%ocaml.error
      "Don't use browser_only on expressions, use switch%platform instead"]

  $ ./standalone.exe -impl attr_expr.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let a = (1 [@melange_only])
  
  let b =
    [%ocaml.error
      "Don't use native_only on expressions, use switch%platform instead"]
  
  let c = (1 [@browser_only])

let%melange_only and [%melange_only ...]

  $ cat > ext.ml << EOF
  > let%melange_only f (x : int) = x + 1
  > let%melange_only g ?(a = 1) b = a + b
  > let%melange_only h = Webapi.Dom.getElementById
  > let on_click = [%melange_only fun event -> Js.log event]
  > let not_a_function = [%melange_only 1]
  > [%%melange_only let ( let+ ) = fun p f -> map f p]
  > EOF

  $ ./standalone.exe -impl ext.ml -js | ocamlformat - --enable-outside-detected-project --impl
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
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
   (fun x ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "f")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (g
       [@alert
         melange_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
   (fun ?a ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "g")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (h
       [@alert
         melange_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
    Obj.magic () [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let on_click event = Ppx_platform_runtime.fail_impossible_action_in_ssr "event"
  
  let not_a_function =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  
  let (( let+ )
       [@alert
         melange_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
   (fun p ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "let+")
    [@alert "-melange_only"]
  [@@warning "-27-32"]

The generated native code carries a melange_only alert for the new name and a browser_only alert for the old one

  $ cat > alert.ml << EOF
  > let%melange_only new_name x = x
  > let%browser_only old_name x = x
  > EOF

  $ ./standalone.exe -impl alert.ml | ocamlformat - --enable-outside-detected-project --impl
  let (new_name
       [@alert
         melange_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
   (fun x ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "new_name")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let (old_name
       [@alert
         browser_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%browser_only \
            function."]) =
   (fun x ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "old_name")
    [@alert "-browser_only"]
  [@@warning "-27-32"]

A floating attribute at the start of a file drops the whole file

  $ cat > floating.ml << EOF
  > [@@@melange_only]
  > let x = 1
  > EOF

  $ ./standalone.exe -impl floating.ml | ocamlformat - --enable-outside-detected-project --impl

  $ ./standalone.exe -impl floating.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let x = 1

Mixed old and new names in one file

  $ cat > mixed.ml << EOF
  > let%browser_only old_fn x = x
  > let%melange_only new_fn x = x
  > let a = match%platform () with Server -> 1 | Melange -> 2
  > let b = 1 [@@browser_only]
  > let c = 2 [@@melange_only]
  > let d = 3 [@@platform js]
  > let e = 4 [@@native_only]
  > let f = 5 [@@platform native]
  > EOF

  $ ./standalone.exe -impl mixed.ml -js | ocamlformat - --enable-outside-detected-project --impl
  let old_fn x = x
  let new_fn x = x
  let a = 2
  let b = 1 [@@browser_only]
  let c = 2 [@@melange_only]
  let d = 3 [@@platform js]

  $ ./standalone.exe -impl mixed.ml | ocamlformat - --enable-outside-detected-project --impl
  let (old_fn
       [@alert
         browser_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%browser_only \
            function."]) =
   (fun x ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "old_fn")
    [@alert "-browser_only"]
  [@@warning "-27-32"]
  
  let (new_fn
       [@alert
         melange_only
           "This expression is marked to only run on the browser where \
            JavaScript can run. You can only use it inside a let%melange_only \
            function."]) =
   (fun x ->
    Ppx_platform_runtime.fail_impossible_action_in_ssr "new_fn")
    [@alert "-melange_only"]
  [@@warning "-27-32"]
  
  let a = 1
  let e = 4 [@@native_only]
  let f = 5 [@@platform native]

The -melange flag is not registered: server-reason-react.ppx registers it, and
ppxlib runs only one handler for a duplicated flag.

  $ ./standalone.exe -impl mixed.ml -melange 2>&1 | head -2
  ./standalone.exe: unknown option '-melange'.
  standalone.exe [extra_args] [<files>]
