Detecting in-scope identifiers inside melange_only on native.

On native, a name used only in discarded code gets a `let _ = name` at the kept
position when the name is a plain name bound locally in the enclosing
expression: let bindings, function parameters, pattern variables, for-loop
indices, binding operators, object self and instance variables, and the names
of the enclosing `let rec`. Top-level values, module paths and names from opens
or includes never get one.

A local let%melange_only stub has the melange_only alert, so a native use of
it fails under -alert @melange_only (syntax_bindings.t section 7). The inputs
that use a local stub outside a Melange branch mark the use with
[@alert "-melange_only"].

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. Local names compile with zero warnings under -w +A -warn-error +A

  $ cat > supported.mli << 'EOF'
  > val use_state_example : unit -> int
  > val enclosing_params :
  >   int -> label:string -> ?opt:int -> (int * int) -> unit -> unit
  > val use_rec : int -> unit [@@alert melange_only]
  > val use_let_unit : int -> unit
  > val use_function_cases : int -> unit [@@alert melange_only]
  > val use_constrained_fun : int -> unit
  > val use_default_param : ?abort:int -> ?base:string -> unit -> unit [@@alert melange_only]
  > val use_shadowed_default : int -> ?x:int -> unit -> unit
  > val use_melange_only_default : ?el:int -> unit -> unit [@@alert melange_only]
  > val use_enclosing_constructs : int option -> int list -> unit
  > val use_sequential_local_melange_only : int -> unit -> unit
  > val use_object : unit -> < run : unit -> unit >
  > EOF

  $ cat > supported_input.ml << 'EOF'
  > (* Local React.useState + React.useEffect with [%melange_only fun ...] *)
  > let use_state init = (init, fun _ -> ())
  > let use_effect (f : unit -> unit option) = ignore f
  > 
  > let use_state_example () =
  >   let a, set_a = use_state 4 in
  >   use_effect [%melange_only fun () -> set_a 33; None];
  >   a
  > 
  > (* Enclosing function parameters: positional, labelled, optional, destructured *)
  > let enclosing_params pos ~label ?opt (p1, p2 as pair) =
  >   let%melange_only handler evt =
  >     Js.log (pos, label, opt, p1, p2, pair, evt)
  >   in
  >   fun () -> ignore handler [@alert "-melange_only"]
  > 
  > (* Recursive let%melange_only (avoids Warning 39 unused rec) *)
  > let%melange_only rec use_rec n =
  >   if n > 0 then use_rec (n - 1) else Js.log n
  > 
  > (* Local let%melange_only () = ... *)
  > let use_let_unit x =
  >   let%melange_only () = Js.log x in
  >   ()
  > 
  > (* Pfunction_cases (function | ... -> ...) *)
  > let%melange_only use_function_cases = function
  >   | x when x < 0 -> Js.log x
  >   | _ -> Js.log ()
  > 
  > (* Constrained [%melange_only (fun ... : ...)] *)
  > let use_constrained_fun =
  >   [%melange_only (fun x -> Js.log x : int -> unit)]
  > 
  > (* Optional parameter with a default expression *)
  > let%melange_only use_default_param ?abort ?(base = "https://example.com") () =
  >   Js.log (abort, base)
  > 
  > (* Default parameter referencing the enclosing x that is shadowed by parameter ?x *)
  > let use_shadowed_default x =
  >   let%melange_only f ?(x = x) () = Js.log x in
  >   (f [@alert "-melange_only"])
  > 
  > (* Default parameter referencing a Melange-only module is safely ignored *)
  > let%melange_only use_melange_only_default ?(el = Webapi.Dom.document) () =
  >   Js.log el
  > 
  > (* Enclosing match, try, for, let* bindings *)
  > let ( let* ) o f = Option.bind o f
  > 
  > let use_enclosing_constructs opt xs =
  >   let _ =
  >     let* bound_letop = opt in
  >     let h = [%melange_only fun () -> Js.log bound_letop] in
  >     ignore h;
  >     Some ()
  >   in
  >   (match xs with
  >   | hd :: tl ->
  >       let h = [%melange_only fun () -> Js.log (hd, tl)] in
  >       ignore h
  >   | [] -> ());
  >   (try ()
  >    with exn ->
  >      let h = [%melange_only fun () -> Js.log exn] in
  >      ignore h);
  >   for i = 0 to 1 do
  >     let h = [%melange_only fun () -> Js.log i] in
  >     ignore h
  >   done
  > 
  > (* Sequential local let%melange_only where the second calls the first *)
  > let use_sequential_local_melange_only x =
  >   let%melange_only first () = Js.log x in
  >   let%melange_only second () = first () in
  >   (second [@alert "-melange_only"])
  > 
  > (* Object self and instance val *)
  > let use_object () =
  >   object (self)
  >     val state = 1
  >     method run = [%melange_only fun () -> Js.log (self, state)]
  >   end
  > EOF

  $ ./standalone.exe -impl supported_input.ml | ocamlformat - --enable-outside-detected-project --impl > supported.ml
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only supported.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . supported.ml

Verify selected generated expansions:

  $ grep -A 5 "let use_state_example" supported.ml
  let use_state_example () =
    let a, set_a = use_state 4 in
    use_effect (fun _ ->
        let _ = set_a in
        Ppx_platform.fail_melange_only "supported_input.ml:7:14");
    a

  $ grep -A 6 "let use_shadowed_default" supported.ml
  let use_shadowed_default x =
    let (f
         [@alert
           melange_only
             "This value only exists in the Melange build. Use it inside a \
              let%melange_only function, or a Melange branch of match%platform."])
        =

2. Shadowing and genuinely unused bindings STILL warn on native

  $ cat > shadowing.mli << 'EOF'
  > val use_shadowed : int -> unit -> unit
  > val use_nonrec_rhs : int -> unit -> unit
  > val use_param_shadow : int -> int -> unit
  > val use_state_with_unused : unit -> unit
  > EOF

  $ cat > shadowing_input.ml << 'EOF'
  > (* Enclosing parameter shadowed by inner let: it is NOT used and still warns W27 *)
  > let use_shadowed shadowed_by_let =
  >   let%melange_only f () =
  >     let shadowed_by_let = 2 in
  >     Js.log shadowed_by_let
  >   in
  >   (f [@alert "-melange_only"])
  > 
  > (* Non-rec let x = x + 1 uses the enclosing x in its RHS: it IS used (no W27) *)
  > let use_nonrec_rhs used_in_nonrec_rhs =
  >   let%melange_only f () =
  >     let used_in_nonrec_rhs = used_in_nonrec_rhs + 1 in
  >     Js.log used_in_nonrec_rhs
  >   in
  >   (f [@alert "-melange_only"])
  > 
  > (* Parameter shadows the enclosing parameter: it is NOT used and still warns W27 *)
  > let use_param_shadow shadowed_by_param =
  >   let%melange_only f shadowed_by_param = Js.log shadowed_by_param in
  >   (f [@alert "-melange_only"])
  > 
  > (* Unused sibling binding in useState still warns W27 while set_a does not *)
  > let use_state init = (init, fun _ -> ())
  > let use_effect (f : unit -> unit option) = ignore f
  > let use_state_with_unused () =
  >   let unused_a, set_a = use_state 4 in
  >   use_effect [%melange_only fun () -> set_a 33; None]
  > EOF

  $ ./standalone.exe -impl shadowing_input.ml | ocamlformat - --enable-outside-detected-project --impl > shadowing.ml
  $ ocamlc -c -w +A shadowing.mli
  $ ocamlc -c -w +A -I . shadowing.ml
  File "shadowing.ml", line 1, characters 17-32:
  1 | let use_shadowed shadowed_by_let =
                       ^^^^^^^^^^^^^^^
  Warning 27 [unused-var-strict]: unused variable shadowed_by_let.
  
  File "shadowing.ml", line 27, characters 21-38:
  27 | let use_param_shadow shadowed_by_param =
                            ^^^^^^^^^^^^^^^^^
  Warning 27 [unused-var-strict]: unused variable shadowed_by_param.
  
  File "shadowing.ml", line 45, characters 6-14:
  45 |   let unused_a, set_a = use_state 4 in
             ^^^^^^^^
  Warning 27 [unused-var-strict]: unused variable unused_a.

3. Top-level values, module paths, opens, includes, local modules and
first-class modules get no ignore. The output compiles; the names used only in
discarded code still warn on native.

  $ cat > not_local.mli << 'EOF'
  > val top_level_caller : unit -> unit
  > val use_pexp_ident : unit -> unit [@@alert melange_only]
  > val use_default_param : ?base:string -> unit -> unit [@@alert melange_only]
  > val use_inline_include_and_open : unit -> unit [@@alert melange_only]
  > val use_local_modules : (module Set.S) -> unit
  > module Use_functor : functor (Arg : sig type t val go : t -> unit end) -> sig
  >   val run : Arg.t -> unit [@@alert melange_only]
  > end
  > EOF

  $ cat > not_local_input.ml << 'EOF'
  > (* Top-level values, operators, binding operators, primitives, and earlier let%melange_only *)
  > let top_helper x = x + 1
  > let ( ++ ) a b = a ^ b
  > let ( let+ ) x f = f x
  > external ext_fn : int -> int = "%identity"
  > let [@melange_only] dropped_js_only = Js.null
  > 
  > let%melange_only mel_helper x = Js.log (top_helper x)
  > 
  > let top_level_caller =
  >   [%melange_only
  >     fun () ->
  >       let+ v = ext_fn 1 in
  >       mel_helper v;
  >       Js.log (dropped_js_only, "a" ++ "b")]
  > 
  > (* Pexp_ident pointing to a top-level value *)
  > let ident_target () = ()
  > let%melange_only use_pexp_ident = ident_target
  > 
  > (* Default parameter expression referencing a top-level value *)
  > let default_base = "https://example.com"
  > let%melange_only use_default_param ?(base = default_base) () =
  >   Js.log base
  > 
  > (* Inline include struct / open struct / inline constrained include *)
  > include struct
  >   let from_inline_include = 1
  > end
  > 
  > open struct
  >   let from_inline_open = 3
  > end
  > 
  > include (
  >   struct
  >     let from_inline_sig_include = 4
  >   end : sig
  >     val from_inline_sig_include : int
  >   end)
  > 
  > let%melange_only use_inline_include_and_open () =
  >   Js.log (from_inline_include, from_inline_open, from_inline_sig_include)
  > 
  > (* Module paths, aliases, top-level open/include, local let module, and first-class module unpacks *)
  > module Local_struct = struct
  >   let member = 10
  > end
  > 
  > module Local_alias = Local_struct
  > 
  > module Opened_local = struct
  >   let from_opened_local = 30
  > end
  > open Opened_local
  > 
  > module Included_local = struct
  >   let from_included_local = 40
  > end
  > include Included_local
  > 
  > let use_local_modules (module Unpacked : Set.S) =
  >   let module Local_in_fn = struct
  >     let local_val = 60
  >   end in
  >   let h =
  >     [%melange_only
  >       fun () ->
  >         Js.log
  >           ( Local_struct.member,
  >             Local_alias.member,
  >             from_opened_local,
  >             from_included_local,
  >             Local_in_fn.local_val,
  >             Unpacked.empty )]
  >   in
  >   ignore h
  > 
  > (* Functor parameter with inline signature *)
  > module Use_functor (Arg : sig type t val go : t -> unit end) = struct
  >   let%melange_only run v = Arg.go v
  > end
  > EOF

  $ ./standalone.exe -impl not_local_input.ml | ocamlformat - --enable-outside-detected-project --impl > not_local.ml
  $ grep -n "let _ = \|let module _" not_local.ml
  13:  let _ = x in
  41:  let _ = base in
  110:    let _ = v in
  $ ocamlc -c -w +A -alert @melange_only not_local.mli
  $ ocamlc -c -w +A -alert @melange_only -I . not_local.ml
  File "not_local.ml", line 1, characters 4-14:
  1 | let top_helper x = x + 1
          ^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value top_helper.
  
  File "not_local.ml", line 2, characters 4-10:
  2 | let ( ++ ) a b = a ^ b
          ^^^^^^
  Warning 32 [unused-value-declaration]: unused value ++.
  
  File "not_local.ml", line 3, characters 4-12:
  3 | let ( let+ ) x f = f x
          ^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value let+.
  
  File "not_local.ml", line 5, characters 0-42:
  5 | external ext_fn : int -> int = "%identity"
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value ext_fn.
  
  File "not_local.ml", line 21, characters 4-16:
  21 | let ident_target () = ()
           ^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value ident_target.
  
  File "not_local.ml", line 33, characters 4-16:
  33 | let default_base = "https://example.com"
           ^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value default_base.
  
  File "not_local.ml", line 47, characters 6-25:
  47 |   let from_inline_include = 1
             ^^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value from_inline_include.
  
  File "not_local.ml", line 51, characters 6-22:
  51 |   let from_inline_open = 3
             ^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value from_inline_open.
  
  File "not_local.ml", line 59, characters 6-39:
  59 |       val from_inline_sig_include : int
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value from_inline_sig_include.
  
  File "not_local.ml", line 73, characters 6-12:
  73 |   let member = 10
             ^^^^^^
  Warning 32 [unused-value-declaration]: unused value member.
  
  File "not_local.ml", line 76, characters 0-33:
  76 | module Local_alias = Local_struct
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 60 [unused-module]: unused module Local_alias.
  
  File "not_local.ml", line 79, characters 6-23:
  79 |   let from_opened_local = 30
             ^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value from_opened_local.
  
  File "not_local.ml", line 82, characters 0-17:
  82 | open Opened_local
       ^^^^^^^^^^^^^^^^^
  Warning 33 [unused-open]: unused open Opened_local.
  
  File "not_local.ml", line 85, characters 6-25:
  85 |   let from_included_local = 40
             ^^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value from_included_local.
  
  File "not_local.ml", line 90, characters 30-38:
  90 | let use_local_modules (module Unpacked : Set.S) =
                                     ^^^^^^^^
  Warning 60 [unused-module]: unused module Unpacked.
  
  File "not_local.ml", line 92, characters 8-17:
  92 |     let local_val = 60
               ^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value local_val.
  
  File "not_local.ml", line 91, characters 13-24:
  91 |   let module Local_in_fn = struct
                    ^^^^^^^^^^^
  Warning 60 [unused-module]: unused module Local_in_fn.
  
  File "not_local.ml", line 100, characters 2-20:
  100 |   val go : t -> unit
          ^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value go.
  
  File "not_local.ml", line 97, characters 20-23:
  97 | module Use_functor (Arg : sig
                           ^^^
  Warning 60 [unused-module]: unused module Arg.

Bindings wrapped in `[%%private ...]` are top-level values, so they get no ignore either:

  $ cat > private_input.ml << 'EOF'
  > [%%private let secret = "k"]
  > [%%private let%melange_only private_helper () = secret]
  > 
  > module M = struct
  >   [%%private let hidden = 1]
  >   let visible = 2
  > end
  > 
  > let use_priv =
  >   [%melange_only fun () -> ignore (secret, private_helper (), M.visible)]
  > 
  > let use_hidden_mod =
  >   [%melange_only fun () -> ignore M.hidden]
  > EOF

  $ ./standalone.exe -impl private_input.ml | ocamlformat - --enable-outside-detected-project --impl
  [%%private let secret = "k"]
  
  [%%private
  let (private_helper
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun _ ->
    Ppx_platform.fail_melange_only "private_helper")
    [@alert "-melange_only"]
  [@@warning "-32"]]
  
  module M = struct
    [%%private let hidden = 1]
  
    let visible = 2
  end
  
  let use_priv _ = Ppx_platform.fail_melange_only "private_input.ml:10:3"
  let use_hidden_mod _ = Ppx_platform.fail_melange_only "private_input.ml:13:3"
