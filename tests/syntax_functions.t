Function forms, as the discarded definition and as the enclosing function.

Each input compiles in native mode and in Melange mode (-js) under
-w +A -warn-error +A. The native build has no Js module, so any Melange code
left in the native output fails to compile. The Melange build uses a small Js
stub in mel/. Each input has an .mli that fixes the types of the native output.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

  $ mkdir mel
  $ cat > mel/js.ml << 'EOF'
  > let log _ = ()
  > let log2 _ _ = ()
  > EOF
  $ ocamlc -c mel/js.ml

1. Parameter forms of a discarded top-level function: one positional
parameter, labelled, labelled with a type, labelled with a pattern, optional,
optional with a default, unit, tuple and record destructuring. The native
function keeps every parameter, without its type and default, and ignores
the names that they bind.

  $ cat > params.mli << 'EOF'
  > val one : int -> unit [@@alert melange_only]
  > val labelled : x:int -> unit [@@alert melange_only]
  > val labelled_typed : x:int -> y:string -> unit [@@alert melange_only]
  > val labelled_pat : x:int * int -> unit [@@alert melange_only]
  > val optional : ?x:int -> unit -> unit [@@alert melange_only]
  > val optional_default : ?x:int -> unit -> unit [@@alert melange_only]
  > val unit_param : unit -> unit [@@alert melange_only]
  > val tuple_param : int * string -> unit [@@alert melange_only]
  > type r = { a : int; b : string }
  > val record_param : r -> unit [@@alert melange_only]
  > EOF

  $ cat > params_input.ml << 'EOF'
  > let%melange_only one x = Js.log x
  > let%melange_only labelled ~x = Js.log x
  > let%melange_only labelled_typed ~(x : int) ~(y : string) = Js.log (x, y)
  > let%melange_only labelled_pat ~x:(a, b) = Js.log (a + b)
  > let%melange_only optional ?x () = Js.log x
  > let%melange_only optional_default ?(x = 1) () = Js.log x
  > let%melange_only unit_param () = Js.log 1
  > let%melange_only tuple_param (a, b) = Js.log (a, b)
  > type r = { a : int; b : string }
  > let%melange_only record_param { a; b } = Js.log (a, b)
  > EOF

  $ ./standalone.exe -impl params_input.ml | ocamlformat - --enable-outside-detected-project --impl > params_native.ml
  $ ./standalone.exe -impl params_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > params_js.ml
  $ sed -n '/^ (fun/,/fail_melange_only/p' params_native.ml
   (fun x ->
    let _ = x in
    Ppx_platform.fail_melange_only "one")
   (fun ~x ->
    let _ = x in
    Ppx_platform.fail_melange_only "labelled")
   (fun ~x ~y ->
    let _ = x in
    let _ = y in
    Ppx_platform.fail_melange_only "labelled_typed")
   (fun ~x:(a, b) ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "labelled_pat")
   (fun ?x () ->
    let _ = x in
    Ppx_platform.fail_melange_only "optional")
   (fun ?x () ->
    let _ = x in
    Ppx_platform.fail_melange_only "optional_default")
   (fun () ->
    Ppx_platform.fail_melange_only "unit_param")
   (fun (a, b) ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "tuple_param")
   (fun { a; b } ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "record_param")
  $ cp params.mli params_native.mli
  $ cp params.mli params_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only params_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . params_native.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only params_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel params_js.ml

2. Type annotations and other right-hand sides of a discarded top-level
function: `type a.` annotations, `function` cases with a guard, a return type
constraint, a coercion in the body, a polymorphic annotation, an explicit
`fun`, a value constraint, a nested `fun`, a function that returns a function,
an identifier, and binding attributes. The native output drops the
annotations; the .mli checks that the types still match. The .mli exports
`target`: a top-level value used only by discarded code otherwise warns 32.

  $ cat > forms.mli << 'EOF'
  > val newtype_constrained : 'a list -> int [@@alert melange_only]
  > val cases : int -> string [@@alert melange_only]
  > val return_constraint : int -> string [@@alert melange_only]
  > val coerced : int -> [ `A | `B ] [@@alert melange_only]
  > val poly : 'a -> 'a [@@alert melange_only]
  > val explicit_fun : int -> unit [@@alert melange_only]
  > val annotated : int -> int -> int [@@alert melange_only]
  > val nested : int -> int -> int [@@alert melange_only]
  > val returns_fun : int -> int -> int [@@alert melange_only]
  > val target : int -> unit
  > val ident_rhs : int -> unit [@@alert melange_only]
  > val with_attrs : int -> unit [@@alert melange_only]
  > EOF

  $ cat > forms_input.ml << 'EOF'
  > let%melange_only newtype_constrained : type a. a list -> int = fun l -> List.length l
  > let%melange_only cases = function
  >   | 0 -> "zero"
  >   | n when n < 0 -> "neg"
  >   | _ -> "pos"
  > let%melange_only return_constraint x : string = Js.log x; "s"
  > let%melange_only coerced x : [ `A | `B ] = ((if x > 0 then `A else `B) :> [ `A | `B ])
  > let%melange_only poly : 'a. 'a -> 'a = fun x -> x
  > let%melange_only explicit_fun = fun x -> Js.log x
  > let%melange_only annotated : int -> int -> int = fun a b -> a + b
  > let%melange_only nested x = fun y -> x + y
  > let%melange_only returns_fun x = let g y = x + y in g
  > let target (_ : int) = ()
  > let%melange_only ident_rhs = target
  > let%melange_only with_attrs x = Js.log x [@@inline] [@@ocaml.doc "doc"]
  > EOF

  $ ./standalone.exe -impl forms_input.ml | ocamlformat - --enable-outside-detected-project --impl > forms_native.ml
  $ ./standalone.exe -impl forms_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > forms_js.ml
  $ grep -n "^ (fun\|Obj.magic\|let _ =\|fail_melange_only" forms_native.ml
  6: (fun l ->
  7:  let _ = l in
  8:  Ppx_platform.fail_melange_only "newtype_constrained")
  17: (fun _ -> Ppx_platform.fail_melange_only "cases") [@alert "-melange_only"]
  25: (fun x ->
  26:  let _ = x in
  27:  Ppx_platform.fail_melange_only "return_constraint")
  36: (fun x ->
  37:  let _ = x in
  38:  Ppx_platform.fail_melange_only "coerced")
  47: (fun x ->
  48:  let _ = x in
  49:  Ppx_platform.fail_melange_only "poly")
  58: (fun x ->
  59:  let _ = x in
  60:  Ppx_platform.fail_melange_only "explicit_fun")
  69: (fun a b ->
  70:  let _ = a in
  71:  let _ = b in
  72:  Ppx_platform.fail_melange_only "annotated")
  81: (fun x y ->
  82:  let _ = x in
  83:  let _ = y in
  84:  Ppx_platform.fail_melange_only "nested")
  93: (fun x ->
  94:  let _ = x in
  95:  Ppx_platform.fail_melange_only "returns_fun")
  106:  Obj.magic () [@alert "-melange_only"]
  114: (fun x ->
  115:  let _ = x in
  116:  Ppx_platform.fail_melange_only "with_attrs")

The binding attributes [@@inline] and [@@ocaml.doc] are replaced by
[@@warning "-32"] on native; on Melange they stay.

  $ grep -n "inline\|doc" forms_native.ml forms_js.ml
  forms_js.ml:21:let with_attrs x = Js.log x [@@inline] [@@ocaml.doc "doc"]
  $ cp forms.mli forms_native.mli
  $ cp forms.mli forms_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only forms_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . forms_native.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only forms_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel forms_js.ml

3. Enclosing functions. A name bound by the enclosing function (positional,
labelled, optional with a default, tuple, `(type a)`, `function` case, nested
`fun`) or by a local let, and used only in discarded code, gets an ignore.
The discarded function is `[%melange_only fun ...]` as an argument, a record
field value, a tuple element or a return value, a local `let%melange_only` with
a `fun`, a value constraint, a return constraint or [@@attrs], or a
match%platform branch. Default arguments of the discarded function that use
an enclosing local, also in a parameter after the first, keep that local used.

  $ cat > enclosing.mli << 'EOF'
  > type handlers = { on_click : unit -> unit; on_key : int -> unit }
  > val as_argument : int -> unit
  > val as_record_field : string -> handlers
  > val in_tuple : int -> (unit -> unit) * int
  > val returns_melange_fun : int -> int -> unit
  > val constrained_arg : int -> unit
  > val partial_local : int -> unit
  > val labelled_enclosing : x:int -> y:int -> int
  > val optional_enclosing : ?x:int -> ?y:int -> unit -> unit
  > val newtype_enclosing : 'a -> 'a
  > val cases_enclosing : int option -> unit
  > val nested_enclosing : int -> int -> unit
  > val local_forms : int -> unit
  > val local_with_attrs : int -> unit
  > val default_outer_local : int -> unit
  > val later_default : int -> unit
  > val later_labelled_default : int -> unit
  > val platform_params : x:int -> ?y:int -> int * int -> int
  > EOF

  $ cat > enclosing_input.ml << 'EOF'
  > type handlers = { on_click : unit -> unit; on_key : int -> unit }
  > let register (f : unit -> unit) = ignore f
  > let as_argument x = register [%melange_only fun () -> Js.log x]
  > let as_record_field label =
  >   { on_click = [%melange_only fun () -> Js.log label];
  >     on_key = [%melange_only fun key -> Js.log (label, key)] }
  > let in_tuple n = ([%melange_only fun () -> Js.log n], 0)
  > let returns_melange_fun a = [%melange_only fun b -> Js.log (a, b)]
  > let constrained_arg x = register [%melange_only (fun () -> Js.log x : unit -> unit)]
  > let add a b = a + b
  > let partial_local n =
  >   let add_n = add n in
  >   register [%melange_only fun () -> Js.log (add_n 1)]
  > let labelled_enclosing ~x ~y =
  >   let%melange_only f () = Js.log y in
  >   ignore f;
  >   x
  > let optional_enclosing ?x ?(y = 2) () =
  >   let%melange_only f () = Js.log (x, y) in
  >   ignore f
  > let newtype_enclosing (type a) (v : a) : a =
  >   let%melange_only f (w : a) = Js.log w in
  >   ignore f;
  >   v
  > let cases_enclosing = function
  >   | Some n ->
  >       let%melange_only f () = Js.log n in
  >       ignore f
  >   | None -> ()
  > let nested_enclosing a = fun b ->
  >   let%melange_only f () = Js.log (a, b) in
  >   ignore f
  > let local_forms n =
  >   let%melange_only explicit = fun x -> Js.log (n, x) in
  >   let%melange_only annotated : int -> unit = fun x -> Js.log (n, x) in
  >   let%melange_only ret_constraint x : unit = Js.log (n, x) in
  >   ignore (explicit, annotated, ret_constraint)
  > let local_with_attrs x =
  >   let%melange_only f () = Js.log x [@@inline] in
  >   ignore f
  > let default_outer_local x =
  >   let base = x + 1 in
  >   let%melange_only f ?(y = base) () = Js.log y in
  >   ignore f
  > let later_default x =
  >   let base = x + 1 in
  >   let%melange_only f () ?(y = base) () = Js.log y in
  >   ignore f
  > let later_labelled_default x =
  >   let%melange_only f ~a ?(b = a + x) () = Js.log (a, b) in
  >   ignore f
  > let platform_params ~x ?(y = 0) (a, b) =
  >   match%platform () with
  >   | Native -> x
  >   | Melange -> x + y + a + b
  > EOF

  $ ./standalone.exe -impl enclosing_input.ml | ocamlformat - --enable-outside-detected-project --impl > enclosing_native.ml
  $ ./standalone.exe -impl enclosing_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > enclosing_js.ml
  $ cat enclosing_native.ml
  type handlers = { on_click : unit -> unit; on_key : int -> unit }
  
  let register (f : unit -> unit) = ignore f
  
  let as_argument x =
    register (fun () ->
        let _ = x in
        Ppx_platform.fail_melange_only "<unkwnown>")
  
  let as_record_field label =
    {
      on_click =
        (fun () ->
          let _ = label in
          Ppx_platform.fail_melange_only "<unkwnown>");
      on_key =
        (fun key ->
          let _ = key in
          let _ = label in
          Ppx_platform.fail_melange_only "key");
    }
  
  let in_tuple n =
    ( (fun () ->
        let _ = n in
        Ppx_platform.fail_melange_only "<unkwnown>"),
      0 )
  
  let returns_melange_fun a =
   fun b ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "b"
  
  let constrained_arg x =
    register
      (fun () ->
         let _ = x in
         Ppx_platform.fail_melange_only "Js.log x"
        : unit -> unit)
  
  let add a b = a + b
  
  let partial_local n =
    let add_n = add n in
    register (fun () ->
        let _ = add_n in
        Ppx_platform.fail_melange_only "<unkwnown>")
  
  let labelled_enclosing ~x ~y =
    let f () =
      let _ = y in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f;
    x
  
  let optional_enclosing ?x ?(y = 2) () =
    let f () =
      let _ = x in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let newtype_enclosing (type a) (v : a) : a =
    let f w =
      let _ = w in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f;
    v
  
  let cases_enclosing = function
    | Some n ->
        let f () =
          let _ = n in
          Ppx_platform.fail_melange_only "f"
            [@@alert "-melange_only"]
        in
        ignore f
    | None -> ()
  
  let nested_enclosing a =
   fun b ->
    let f () =
      let _ = a in
      let _ = b in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let local_forms n =
    let explicit x =
      let _ = n in
      let _ = x in
      Ppx_platform.fail_melange_only "explicit"
        [@@alert "-melange_only"]
    in
    let annotated x =
      let _ = n in
      let _ = x in
      Ppx_platform.fail_melange_only "annotated"
        [@@alert "-melange_only"]
    in
    let ret_constraint x =
      let _ = n in
      let _ = x in
      Ppx_platform.fail_melange_only "ret_constraint"
        [@@alert "-melange_only"]
    in
    ignore (explicit, annotated, ret_constraint)
  
  let local_with_attrs x =
    let f () =
      let _ = x in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let default_outer_local x =
    let base = x + 1 in
    let f ?y () =
      let _ = base in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let later_default x =
    let base = x + 1 in
    let f () ?y () =
      let _ = base in
      let _ = y in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let later_labelled_default x =
    let f ~a ?b () =
      let _ = a in
      let _ = b in
      let _ = x in
      Ppx_platform.fail_melange_only "f"
        [@@alert "-melange_only"]
    in
    ignore f
  
  let platform_params ~x ?(y = 0) (a, b) =
    let _ = a in
    let _ = b in
    let _ = y in
    x
  $ cp enclosing.mli enclosing_native.mli
  $ cp enclosing.mli enclosing_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only enclosing_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . enclosing_native.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only enclosing_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel enclosing_js.ml

4. Several positional parameters. A discarded top-level function keeps every
parameter and ignores the names that they bind.

  $ cat > several.mli << 'EOF'
  > val several : int -> string -> bool -> unit [@@alert melange_only]
  > EOF
  $ cat > several_input.ml << 'EOF'
  > let%melange_only several a b c = Js.log (a, b, c)
  > EOF
  $ ./standalone.exe -impl several_input.ml | ocamlformat - --enable-outside-detected-project --impl > several_native.ml
  $ ./standalone.exe -impl several_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > several_js.ml
  $ sed -n '/^ (fun/,/fail_melange_only/p' several_native.ml
   (fun a b c ->
    let _ = a in
    let _ = b in
    let _ = c in
    Ppx_platform.fail_melange_only "several")
  $ cp several.mli several_native.mli
  $ cp several.mli several_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only several_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . several_native.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only several_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel several_js.ml

Known issues

The outputs below record the current, wrong behaviour.

5. `?x:(pattern = default)` with a pattern that is not a variable. The native
output drops the default but keeps the pattern, so the pattern must match an
option and the output does not compile. Expected: a parameter that compiles,
such as `?x:_`.

  $ cat > optional_pattern.mli << 'EOF'
  > val optional_pat_default : ?x:int * int -> unit -> unit [@@alert melange_only]
  > EOF
  $ cat > optional_pattern_input.ml << 'EOF'
  > let%melange_only optional_pat_default ?x:((a, b) = (1, 2)) () = Js.log (a, b)
  > EOF
  $ ./standalone.exe -impl optional_pattern_input.ml | ocamlformat - --enable-outside-detected-project --impl > optional_pattern_native.ml
  $ ./standalone.exe -impl optional_pattern_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > optional_pattern_js.ml
  $ sed -n '/^ (fun/,/fail_melange_only/p' optional_pattern_native.ml
   (fun ?x:(a, b) () ->
    let _ = a in
    let _ = b in
    Ppx_platform.fail_melange_only "optional_pat_default")
  $ cp optional_pattern.mli optional_pattern_native.mli
  $ cp optional_pattern.mli optional_pattern_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only optional_pattern_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . optional_pattern_native.ml
  File "optional_pattern_native.ml", line 6, characters 10-14:
  6 |  (fun ?x:(a, b) () ->
                ^^^^
  Error: This pattern matches values of type 'a * 'b
         but a pattern was expected which matches values of type 'c option
  [2]
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only optional_pattern_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel optional_pattern_js.ml

6. A top-level `let%melange_only` whose function has `(type a)` parameters
becomes a stub that keeps `(type a)` but drops the annotations that use it, so
native fails with warning 34 (unused type). A top-level `let%melange_only`
whose right-hand side is an application is kept unchanged on native, with
Melange code and no melange_only alert. Expected: a fail_melange_only stub with
the alert that compiles, as for other functions.

  $ cat > top_newtype.mli << 'EOF'
  > val newtype : 'a -> 'a list [@@alert melange_only]
  > val newtype_two : 'a -> 'b -> unit [@@alert melange_only]
  > val newtype_fun : 'a -> unit [@@alert melange_only]
  > val poly_newtype : 'a -> unit [@@alert melange_only]
  > EOF
  $ cat > top_newtype_input.ml << 'EOF'
  > let%melange_only newtype (type a) (x : a) : a list = Js.log x; [ x ]
  > let%melange_only newtype_two (type a b) (x : a) (y : b) = Js.log (x, y)
  > let%melange_only newtype_fun = fun (type a) (x : a) -> Js.log x
  > let%melange_only poly_newtype : 'a. 'a -> unit = fun (type a) (x : a) -> Js.log x
  > EOF
  $ ./standalone.exe -impl top_newtype_input.ml | ocamlformat - --enable-outside-detected-project --impl > top_newtype_native.ml
  $ ./standalone.exe -impl top_newtype_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > top_newtype_js.ml
  $ sed -n '/^ (fun/,/fail_melange_only/p' top_newtype_native.ml
   (fun (type a) x ->
    let _ = x in
    Ppx_platform.fail_melange_only "newtype")
   (fun (type a) (type b) x y ->
    let _ = x in
    let _ = y in
    Ppx_platform.fail_melange_only "newtype_two")
   (fun (type a) x ->
    let _ = x in
    Ppx_platform.fail_melange_only "newtype_fun")
   (fun (type a) x ->
    let _ = x in
    Ppx_platform.fail_melange_only "poly_newtype")
  $ cp top_newtype.mli top_newtype_native.mli
  $ cp top_newtype.mli top_newtype_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only top_newtype_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . top_newtype_native.ml
  File "top_newtype_native.ml", line 6, characters 12-13:
  6 |  (fun (type a) x ->
                  ^
  Error (warning 34 [unused-type-declaration]): unused type a.
  
  File "top_newtype_native.ml", line 17, characters 12-13:
  17 |  (fun (type a) (type b) x y ->
                   ^
  Error (warning 34 [unused-type-declaration]): unused type a.
  
  File "top_newtype_native.ml", line 17, characters 21-22:
  17 |  (fun (type a) (type b) x y ->
                            ^
  Error (warning 34 [unused-type-declaration]): unused type b.
  
  File "top_newtype_native.ml", line 29, characters 12-13:
  29 |  (fun (type a) x ->
                   ^
  Error (warning 34 [unused-type-declaration]): unused type a.
  
  File "top_newtype_native.ml", line 40, characters 12-13:
  40 |  (fun (type a) x ->
                   ^
  Error (warning 34 [unused-type-declaration]): unused type a.
  [2]
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only top_newtype_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel top_newtype_js.ml

  $ cat > top_kept.mli << 'EOF'
  > val partial : int -> unit [@@alert melange_only]
  > EOF
  $ cat > top_kept_input.ml << 'EOF'
  > let%melange_only partial = Js.log2 1
  > EOF
  $ ./standalone.exe -impl top_kept_input.ml | ocamlformat - --enable-outside-detected-project --impl > top_kept_native.ml
  $ ./standalone.exe -impl top_kept_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > top_kept_js.ml
  $ cat top_kept_native.ml
  let partial = Js.log2 1
  $ cp top_kept.mli top_kept_native.mli
  $ cp top_kept.mli top_kept_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only top_kept_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . top_kept_native.ml
  File "top_kept_native.ml", line 1, characters 14-16:
  1 | let partial = Js.log2 1
                    ^^
  Error: Unbound module Js
  [2]
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only top_kept_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel top_kept_js.ml

7. Function forms that a top-level `let%melange_only` accepts but a local
`let%melange_only` or `[%melange_only ...]` rejects with the "works on function
definitions" error: an identifier, `function` cases, `(type a)` first, and a
coercion `(fun ... :> t)`. Expected: the same stub as at top level.

  $ cat > rejected.mli << 'EOF'
  > val local_ident_rhs : (int -> unit) -> unit
  > val local_function : int -> unit
  > val local_newtype : int -> unit
  > val ext_function : int -> unit
  > val ext_newtype : int -> unit
  > val ext_coerce : int -> unit
  > EOF
  $ cat > rejected_input.ml << 'EOF'
  > let register (f : int -> unit) = ignore f
  > let local_ident_rhs g =
  >   let%melange_only f = g in
  >   register f
  > let local_function n =
  >   let%melange_only f = function 0 -> Js.log n | _ -> () in
  >   register f
  > let local_newtype n =
  >   let%melange_only f (type a) (x : a) = Js.log (n, x) in
  >   register f
  > let ext_function n = register [%melange_only function 0 -> Js.log n | _ -> ()]
  > let ext_newtype n = register [%melange_only fun (type a) (x : a) -> Js.log (n, x)]
  > let ext_coerce n = register [%melange_only (fun x -> Js.log (n, x) :> int -> unit)]
  > EOF
  $ ./standalone.exe -impl rejected_input.ml | ocamlformat - --enable-outside-detected-project --impl > rejected_native.ml
  $ ./standalone.exe -impl rejected_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > rejected_js.ml
  $ grep -c "ocaml.error" rejected_native.ml
  6
  $ cp rejected.mli rejected_native.mli
  $ cp rejected.mli rejected_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only rejected_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . rejected_native.ml
  File "rejected_native.ml", line 5, characters 6-17:
  5 |     [%ocaml.error
            ^^^^^^^^^^^
  Error: [ppx_platform] melange_only works on function definitions. For other
         cases, use switch%platform or feel free to open an issue in
         https://github.com/ml-in-barcelona/ppx_platform.
  [2]
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only rejected_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . -I mel rejected_js.ml

8. The fail_melange_only message of an anonymous `[%melange_only fun ...]` is
the first parameter's name, "<unkwnown>" for a non-variable parameter, or the
printed body for a constrained function. Expected: one stable name. The lines
come from section 3.

  $ grep -n "fail_melange_only" enclosing_native.ml | head -6
  8:      Ppx_platform.fail_melange_only "<unkwnown>")
  15:        Ppx_platform.fail_melange_only "<unkwnown>");
  20:        Ppx_platform.fail_melange_only "key");
  26:      Ppx_platform.fail_melange_only "<unkwnown>"),
  33:  Ppx_platform.fail_melange_only "b"
  39:       Ppx_platform.fail_melange_only "Js.log x"
