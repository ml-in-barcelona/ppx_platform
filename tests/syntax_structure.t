Where discarded code can sit at the structure and module level.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. Top-level let%melange_only and [%%melange_only let ...]: plain, rec, `and`,
with item attributes, with type annotations. The same .mli compiles against the
Native and the Melange output under -w +A -warn-error +A.

  $ cat > top.mli << 'EOF'
  > val plain : int -> int [@@alert melange_only]
  > val loop : int -> unit [@@alert melange_only]
  > val two : int -> int -> int [@@alert melange_only]
  > val other : int -> int [@@alert melange_only]
  > val even : int -> bool [@@alert melange_only]
  > val odd : int -> bool [@@alert melange_only]
  > val with_attrs : int -> int [@@alert melange_only]
  > val annotated : int -> int [@@alert melange_only]
  > val annotated_params : int -> int [@@alert melange_only]
  > val bracket : int -> int [@@alert melange_only]
  > val bracket_rec : int -> unit [@@alert melange_only]
  > EOF

  $ cat > top.ml << 'EOF'
  > let%melange_only plain x = x + 1
  > let%melange_only rec loop n = if n > 0 then loop (n - 1) else ()
  > let%melange_only two a b = a + b
  > and other c = c
  > let%melange_only rec even n = n = 0 || odd (n - 1)
  > and odd n = n <> 0 && even (n - 1)
  > let%melange_only with_attrs (x : int) = x [@@inline never]
  > let%melange_only annotated : int -> int = fun x -> x
  > let%melange_only annotated_params (x : int) : int = x
  > [%%melange_only let bracket x = x + 1]
  > [%%melange_only let rec bracket_rec n = if n > 0 then bracket_rec (n - 1)]
  > EOF

  $ mkdir native js
  $ cp ppx_platform.cm* native/
  $ cp ppx_platform.cm* js/

  $ ./standalone.exe -impl top.ml | ocamlformat - --enable-outside-detected-project --impl > native/top.ml
  $ ./standalone.exe -impl top.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/top.ml
  $ cp top.mli native/
  $ cp top.mli js/
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only native/top.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I native native/top.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only js/top.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I js js/top.ml

Every binding becomes a stub that raises. A recursive binding ignores its own
name, so `let rec` stays used:

  $ grep -c 'Ppx_platform.fail_melange_only' native/top.ml
  11
  $ grep -A 9 '^let rec (loop' native/top.ml
  let rec (loop
           [@alert
             melange_only
               "This value only exists in the Melange build. Use it inside a \
                let%melange_only function, or a Melange branch of \
                match%platform."]) =
   (fun n ->
    let _ = loop in
    let _ = n in
    Ppx_platform.fail_melange_only "loop")

With -js the extension goes away and the code stays as written:

  $ cat js/top.ml
  let plain x = x + 1
  let rec loop n = if n > 0 then loop (n - 1) else ()
  
  let two a b = a + b
  and other c = c
  
  let rec even n = n = 0 || odd (n - 1)
  and odd n = n <> 0 && even (n - 1)
  
  let with_attrs (x : int) = x [@@inline never]
  let annotated : int -> int = fun x -> x
  let annotated_params (x : int) : int = x
  let bracket x = x + 1
  let rec bracket_rec n = if n > 0 then bracket_rec (n - 1)

2. [%%melange_only ...] supports one let binding. Any other payload is a ppx
error at the item, in both modes:

  $ for item in 'type t = int' 'module M = struct end' 'external f : int -> int = "%identity"' 'open List' 'exception E' 'print_endline "x"' 'let x = 1 let y = 2'; do
  >   echo "$item"
  >   printf '[%%%%melange_only %s]\n' "$item" > unsupported.ml
  >   ./standalone.exe -impl unsupported.ml > unsupported_native.ml
  >   ./standalone.exe -impl unsupported.ml -js > unsupported_js.ml
  >   ocamlc -c unsupported_native.ml 2>&1 | grep -A 1 Error
  >   ocamlc -c unsupported_js.ml 2>&1 | grep -A 1 Error
  > done
  type t = int
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  module M = struct end
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  external f : int -> int = "%identity"
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  open List
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  exception E
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  print_endline "x"
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  let x = 1 let y = 2
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].
  Error: [ppx_platform] [%%melange_only ...] supports one let binding. For
         other structure items, use [@@melange_only].

3. [@@melange_only] and [@@native_only] on every kind of structure item. The
Native and the Melange output export different items, so one .mli cannot
match both; these files compile without an .mli, with warning 70
(missing-mli) off.

  $ cat > items.ml << 'EOF'
  > let v_native = 1 [@@native_only]
  > let v_melange = 2 [@@melange_only]
  > let[@native_only] v_native_prefix = 1
  > let[@melange_only] v_melange_prefix = 2
  > type t_native = int [@@native_only]
  > type t_melange = string [@@melange_only]
  > type ext = ..
  > type ext += Ext_native [@@native_only]
  > type ext += Ext_melange [@@melange_only]
  > module M_native = struct let v = 1 end [@@native_only]
  > module M_melange = struct let v = 2 end [@@melange_only]
  > module type S_native = sig end [@@native_only]
  > module type S_melange = sig end [@@melange_only]
  > external e_native : int -> int = "%identity" [@@native_only]
  > external e_melange : int -> int = "%identity" [@@melange_only]
  > open Stdlib.List [@@melange_only]
  > let uses_open = length [] [@@melange_only]
  > include struct let inc_native = 3 end [@@native_only]
  > include struct let inc_melange = 4 end [@@melange_only]
  > exception E_native [@@native_only]
  > exception E_melange [@@melange_only]
  > class c_native = object end [@@native_only]
  > class c_melange = object end [@@melange_only]
  > let%melange_only stub_and_attr x = x [@@melange_only]
  > EOF

  $ ./standalone.exe -impl items.ml | ocamlformat - --enable-outside-detected-project --impl > native/items.ml
  $ ./standalone.exe -impl items.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/items.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert @melange_only -I native native/items.ml
  $ ocamlc -c -w +A-70 -warn-error +A -alert -melange_only -I js js/items.ml

Native keeps the [@@native_only] items and removes the attribute. A
let%melange_only binding with [@@melange_only] becomes a stub instead of going
away:

  $ cat native/items.ml
  let v_native = 1
  let v_native_prefix = 1
  
  type t_native = int
  type ext = ..
  type ext += Ext_native
  
  module M_native = struct
    let v = 1
  end
  
  module type S_native = sig end
  
  external e_native : int -> int = "%identity"
  
  include struct
    let inc_native = 3
  end
  
  exception E_native
  
  class c_native = object end
  
  let (stub_and_attr
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "stub_and_attr")
    [@alert "-melange_only"]
  [@@warning "-32"]

The Melange output also removes the attribute from the items it keeps:

  $ cat js/items.ml
  let v_melange = 2
  let v_melange_prefix = 2
  
  type t_melange = string
  type ext = ..
  type ext += Ext_melange
  
  module M_melange = struct
    let v = 2
  end
  
  module type S_melange = sig end
  
  external e_melange : int -> int = "%identity"
  
  open Stdlib.List
  
  let uses_open = length []
  
  include struct
    let inc_melange = 4
  end
  
  exception E_melange
  
  class c_melange = object end
  
  let stub_and_attr x = x

A platform attribute in a position that the ppx does not evaluate is an error
in both modes, so the code it marks cannot stay in the wrong build: a class
field, an extension constructor, an inline record field, a type expression, and
one binding of a local `let ... and ...`:

  $ for item in 'class c = object method b = 1 [@@melange_only] end' 'type ext = .. type ext += B of int [@melange_only]' 'type v = A of { x : int [@melange_only] }' 'let y : (int [@melange_only]) = 1' 'let both () = let a = 1 [@@melange_only] and b = 2 in a + b'; do
  >   echo "$item"
  >   echo "$item" > unsupported_attr.ml
  >   ./standalone.exe -impl unsupported_attr.ml 2>&1 | grep -A 2 Error
  >   ./standalone.exe -impl unsupported_attr.ml -js 2>&1 | grep -A 2 Error
  > done
  class c = object method b = 1 [@@melange_only] end
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  type ext = .. type ext += B of int [@melange_only]
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  type v = A of { x : int [@melange_only] }
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  let y : (int [@melange_only]) = 1
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  let both () = let a = 1 [@@melange_only] and b = 2 in a + b
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.
  Error: [ppx_platform] [@melange_only] is not supported here. Use it on a structure or signature item, a constructor or record field of a type definition, a polymorphic variant tag, a pattern or an expression.

A floating [@@@melange_only] or [@@@native_only] as the first item of a file
or a struct keeps or drops the whole rest of it:

  $ cat > floating.ml << 'EOF'
  > module Mel = struct
  >   [@@@melange_only]
  >   let v = 1
  > end
  > module Nat = struct
  >   [@@@native_only]
  >   let v = 2
  > end
  > EOF
  $ ./standalone.exe -impl floating.ml | ocamlformat - --enable-outside-detected-project --impl
  module Mel = struct end
  
  module Nat = struct
    let v = 2
  end

  $ ./standalone.exe -impl floating.ml -js | ocamlformat - --enable-outside-detected-project --impl
  module Mel = struct
    let v = 1
  end
  
  module Nat = struct end

  $ printf '[@@@melange_only]\nlet x = 1\n' > floating_file.ml
  $ ./standalone.exe -impl floating_file.ml | wc -c
  0
  $ ./standalone.exe -impl floating_file.ml -js
  let x = 1

A floating [@@@melange_only] or [@@@native_only] after the first item is a ppx
error at the attribute:

  $ cat > floating_mid.ml << 'EOF'
  > module Mid = struct
  >   let before = 0
  >   [@@@melange_only]
  >   let after = 1
  > end
  > EOF
  $ ./standalone.exe -impl floating_mid.ml | ocamlformat - --enable-outside-detected-project --impl
  module Mid = struct
    let before = 0
  
    [%%ocaml.error
    "[ppx_platform] [@@@melange_only] works only as the first item of a \
     structure or a signature"]
  
    let after = 1
  end
  $ ./standalone.exe -impl floating_mid.ml > floating_mid_native.ml
  $ ocamlc -c floating_mid_native.ml 2>&1 | grep -A 1 Error
  Error: [ppx_platform] [@@@melange_only] works only as the first item of a
         structure or a signature
  $ printf 'val before : int\n[@@@native_only]\nval after : int\n' > floating_mid.mli
  $ ./standalone.exe -intf floating_mid.mli -js > floating_mid_js.mli
  $ ocamlc -c floating_mid_js.mli 2>&1 | grep -A 1 Error
  Error: [ppx_platform] [@@@native_only] works only as the first item of a
         structure or a signature

4. let%melange_only and match%platform inside modules: struct, nested struct,
a struct with a module type constraint, a functor body, an applied functor,
`module rec`, `include struct`, and top-level `let () = match%platform`. The
.mli names each melange_only value with [@@alert melange_only]; without it the
Native signature check reports the alert.

  $ cat > modules.mli << 'EOF'
  > module M : sig
  >   val in_struct : int -> int [@@alert melange_only]
  >   module Nested : sig
  >     val nested : string -> unit [@@alert melange_only]
  >   end
  > end
  > module type S = sig
  >   val f : int -> int [@@alert melange_only]
  >   val g : int -> int
  > end
  > module Constrained : S
  > module F (_ : sig val base : int end) : sig
  >   val from_functor : int -> int [@@alert melange_only]
  >   val kept : int -> int
  > end
  > module Applied : sig
  >   val from_functor : int -> int [@@alert melange_only]
  >   val kept : int -> int
  > end
  > module rec R1 : sig val r1 : int -> int [@@alert melange_only] end
  > and R2 : sig val r2 : int -> int end
  > val from_include : int -> int [@@alert melange_only]
  > val top_value : int
  > EOF

  $ cat > modules.ml << 'EOF'
  > module M = struct
  >   let%melange_only in_struct x = x + 1
  >   module Nested = struct
  >     let%melange_only nested (s : string) = print_endline s
  >   end
  > end
  > 
  > module type S = sig
  >   val f : int -> int [@@alert melange_only]
  >   val g : int -> int
  > end
  > 
  > module Constrained : S = struct
  >   let%melange_only f x = x * 2
  >   let g x = x
  > end
  > 
  > module F (X : sig val base : int end) = struct
  >   let%melange_only from_functor y = X.base + y
  >   let kept y = match%platform () with Native -> X.base | Melange -> X.base + y
  > end
  > 
  > module Applied = F (struct let base = 1 end)
  > 
  > module rec R1 : sig
  >   val r1 : int -> int [@@alert melange_only]
  > end = struct
  >   let%melange_only r1 x = R2.r2 x
  > end
  > and R2 : sig
  >   val r2 : int -> int
  > end = struct
  >   let r2 x = x
  > end
  > 
  > include struct
  >   let%melange_only from_include x = x
  > end
  > 
  > let () = match%platform () with Native -> print_endline "native" | Melange -> print_endline "melange"
  > let top_value = match%platform () with Native -> 1 | Melange -> 2
  > EOF

  $ ./standalone.exe -impl modules.ml | ocamlformat - --enable-outside-detected-project --impl > native/modules.ml
  $ ./standalone.exe -impl modules.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/modules.ml
  $ cp modules.mli native/
  $ cp modules.mli js/
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only native/modules.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I native native/modules.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only js/modules.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I js js/modules.ml

The kept function `kept` gets `let _ = y`, because `y` is a parameter used only
in the Melange branch. `X.base` is a module path and gets no ignore. The
top-level match%platform keeps only the Native branch:

  $ grep -n 'let _ = \|fail_melange_only\|let kept\|X.base\|^let ' native/modules.ml
  9:    let _ = x in
  10:    Ppx_platform.fail_melange_only "in_struct")
  22:      let _ = s in
  23:      Ppx_platform.fail_melange_only "nested")
  42:    let _ = x in
  43:    Ppx_platform.fail_melange_only "f")
  61:    let _ = y in
  62:    Ppx_platform.fail_melange_only "from_functor")
  66:  let kept y =
  67:    let _ = y in
  68:    X.base
  85:    let _ = x in
  86:    Ppx_platform.fail_melange_only "r1")
  105:    let _ = x in
  106:    Ppx_platform.fail_melange_only "from_include")
  111:let () = print_endline "native"
  112:let top_value = 1
  $ grep -n '^let ' js/modules.ml
  47:let () = print_endline "melange"
  48:let top_value = 2

5. Names that are not local get no ignore. A top-level value, a local module,
or a functor parameter that only discarded code uses gives an unused warning
(32 or 60) on Native. This is an accepted cost; the output records it so a
change in this behaviour shows here. Native compiles with -w +A without
-warn-error to show the warnings; the Melange build stays clean.

  $ cat > not_local.mli << 'EOF'
  > val uses_helper : unit -> int [@@alert melange_only]
  > val top_match : int
  > module G (_ : sig val base : int end) : sig
  >   val g : int -> int
  > end
  > val uses_local_module : unit -> int
  > EOF

  $ cat > not_local.ml << 'EOF'
  > let helper x = x + 1
  > let%melange_only uses_helper () = helper 1
  > 
  > let only_melange = 10
  > let top_match = match%platform () with Native -> 0 | Melange -> only_melange
  > 
  > module G (X : sig val base : int end) = struct
  >   let g y = match%platform () with Native -> y | Melange -> X.base + y
  > end
  > 
  > module Local = struct let v = 1 end
  > let uses_local_module () = match%platform () with Native -> 0 | Melange -> Local.v
  > EOF

  $ ./standalone.exe -impl not_local.ml | ocamlformat - --enable-outside-detected-project --impl > native/not_local.ml
  $ ./standalone.exe -impl not_local.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/not_local.ml
  $ cp not_local.mli native/
  $ cp not_local.mli js/
  $ grep -c 'let _ = ' native/not_local.ml
  0
  [1]
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only native/not_local.mli
  $ ocamlc -c -w +A -alert @melange_only -I native native/not_local.ml
  File "native/not_local.ml", line 1, characters 4-10:
  1 | let helper x = x + 1
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value helper.
  
  File "native/not_local.ml", line 13, characters 4-16:
  13 | let only_melange = 10
           ^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value only_melange.
  
  File "native/not_local.ml", line 17, characters 2-16:
  17 |   val base : int
         ^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value base.
  
  File "native/not_local.ml", line 16, characters 10-11:
  16 | module G (X : sig
                 ^
  Warning 60 [unused-module]: unused module X.
  
  File "native/not_local.ml", line 24, characters 6-7:
  24 |   let v = 1
             ^
  Warning 32 [unused-value-declaration]: unused value v.
  
  File "native/not_local.ml", lines 23-25, characters 0-3:
  23 | module Local = struct
  24 |   let v = 1
  25 | end
  Warning 60 [unused-module]: unused module Local.
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only js/not_local.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I js js/not_local.ml

6. [%%private ...] wraps structure items; the ppx rewrites inside it. No ppx
here interprets [%%private], so this shows the output only:

  $ cat > private.ml << 'EOF'
  > [%%private let%melange_only helper x = x + 1]
  > [%%private let platform_value = match%platform () with Native -> 1 | Melange -> 2]
  > EOF
  $ ./standalone.exe -impl private.ml | ocamlformat - --enable-outside-detected-project --impl
  [%%private
  let (helper
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "helper")
    [@alert "-melange_only"]
  [@@warning "-32"]]
  
  [%%private let platform_value = 1]
  $ ./standalone.exe -impl private.ml -js | ocamlformat - --enable-outside-detected-project --impl
  [%%private let helper x = x + 1]
  [%%private let platform_value = 2]

A [%%private ...] whose items all go away goes away too:

  $ cat > private_empty.ml << 'EOF'
  > [%%private let dropped = 1 [@@melange_only]]
  > EOF
  $ ./standalone.exe -impl private_empty.ml | ocamlformat - --enable-outside-detected-project --impl

7. A let%melange_only whose right-hand side is not a function or a name is an
error on Native, as for the local form:

  $ cat > non_function.ml << 'EOF'
  > let%melange_only const = 1
  > let%melange_only applied = print_endline "runs on native"
  > [%%melange_only let bracket_applied = print_endline "runs on native"]
  > EOF
  $ ./standalone.exe -impl non_function.ml | ocamlformat - --enable-outside-detected-project --impl
  let const =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  
  let applied =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]
  
  let bracket_applied =
    [%ocaml.error
      "[ppx_platform] melange_only works on function definitions. For other \
       cases, use switch%platform or feel free to open an issue in \
       https://github.com/ml-in-barcelona/ppx_platform."]

A unit binding has nothing to stub: on Native its right-hand side becomes
`()`, as for the local form.

  $ printf 'let%%melange_only () = print_endline "runs on melange"\n' > unit_binding.ml
  $ ./standalone.exe -impl unit_binding.ml | ocamlformat - --enable-outside-detected-project --impl
  let () = ()

8. The Native stub keeps the item attributes of the binding, such as
[@@inline never] or [@@deprecated], after its own [@@warning "-32"]. Native
callers get the deprecation alert:

  $ grep -n 'inline' native/top.ml
  82:[@@warning "-32"] [@@inline never]
  $ cat > deprecated.ml << 'EOF'
  > let%melange_only old x = x [@@deprecated "use new"]
  > EOF
  $ ./standalone.exe -impl deprecated.ml | ocamlformat - --enable-outside-detected-project --impl | grep -c deprecated
  1

9. Inside a `let module` body, a parameter of the enclosing function that only
discarded code uses gets an ignore: in the stub of `l` and before `0` in `v`.
Warning 60 for the unused local module is the accepted cost from section 5.

  $ cat > local_module.mli << 'EOF'
  > val melange_only_in_local_module : int -> int
  > val match_in_local_module : int -> int
  > EOF
  $ cat > local_module.ml << 'EOF'
  > let melange_only_in_local_module x =
  >   let module L = struct
  >     let%melange_only l y = x + y
  >   end in
  >   match%platform () with Native -> 0 | Melange -> L.l 1
  > 
  > let match_in_local_module x =
  >   let module L = struct
  >     let v = match%platform () with Native -> 0 | Melange -> x
  >   end in
  >   L.v
  > EOF
  $ ./standalone.exe -impl local_module.ml | ocamlformat - --enable-outside-detected-project --impl > native/local_module.ml
  $ ./standalone.exe -impl local_module.ml -js | ocamlformat - --enable-outside-detected-project --impl > js/local_module.ml
  $ cp local_module.mli native/
  $ cp local_module.mli js/
  $ grep -n 'let _ = ' native/local_module.ml
  10:      let _ = x in
  11:      let _ = y in
  21:      let _ = x in
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only native/local_module.mli
  $ ocamlc -c -w +A -alert @melange_only -I native native/local_module.ml
  File "native/local_module.ml", line 2, characters 13-14:
  2 |   let module L = struct
                   ^
  Warning 60 [unused-module]: unused module L.
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only js/local_module.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I js js/local_module.ml

Known issues

This case records the current, wrong result.

A. On Native the stub drops the type annotations, so the Native output has a
more general type than the Melange output. An .mli hides this (section 1);
without one the inferred interfaces differ:

  $ ocamlc -i -I native native/top.ml | grep 'two\|annotated'
  val two : 'a -> 'b -> 'c
  val annotated : 'a -> 'b
  val annotated_params : 'a -> 'b
  $ ocamlc -i -I js js/top.ml | grep 'two\|annotated'
  val two : int -> int -> int
  val annotated : int -> int
  val annotated_params : int -> int
