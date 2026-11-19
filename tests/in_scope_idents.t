Detecting in-scope identifiers inside melange_only on native.

Set up a stub Ppx_platform runtime and an interface file so ocamlc -w +A checks
all unused warnings (26, 27, 32, 33, 34, 37, 38, 39, 60, 69) and @melange_only alerts.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. All supported in-scope bindings compile with zero unused warnings under -w +A

  $ cat > supported.mli << 'EOF'
  > val use_state_example : unit -> int
  > val enclosing_params :
  >   int -> label:string -> ?opt:int -> (int * int) -> unit -> unit
  > val top_level_caller : unit -> unit
  > val use_rec : int -> unit [@@alert melange_only]
  > val use_let_unit : int -> unit
  > val use_pexp_ident : unit -> unit [@@alert melange_only]
  > val use_function_cases : int -> unit [@@alert melange_only]
  > val use_constrained_fun : int -> unit
  > val use_default_param : ?abort:int -> unit -> unit [@@alert melange_only]
  > val use_shadowed_default : ?x:int -> unit -> unit [@@alert melange_only]
  > val use_melange_only_default : ?el:int -> unit -> unit [@@alert melange_only]
  > val use_enclosing_constructs : int option -> int list -> unit
  > val use_inline_include_and_open : unit -> unit [@@alert melange_only]
  > val use_local_modules : (module Set.S) -> unit
  > val use_sequential_local_melange_only : int -> unit -> unit
  > val use_object : unit -> < run : unit -> unit >
  > module Use_functor : functor (Arg : sig type t val go : t -> unit end) -> sig
  >   val run : Arg.t -> unit [@@alert melange_only]
  > end
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
  >   fun () -> ignore handler
  > 
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
  > (* Recursive let%melange_only (avoids Warning 39 unused rec) *)
  > let%melange_only rec use_rec n =
  >   if n > 0 then use_rec (n - 1) else Js.log n
  > 
  > (* Local let%melange_only () = ... *)
  > let use_let_unit x =
  >   let%melange_only () = Js.log x in
  >   ()
  > 
  > (* Pexp_ident pointing to an in-scope value *)
  > let ident_target () = ()
  > let%melange_only use_pexp_ident = ident_target
  > 
  > (* Pfunction_cases (function | ... -> ...) *)
  > let cases_helper x = x + 1
  > let%melange_only use_function_cases = function
  >   | x when x < 0 -> Js.log (cases_helper x)
  >   | _ -> Js.log ()
  > 
  > (* Constrained [%melange_only (fun ... : ...)] *)
  > let constrained_helper x = x + 1
  > let use_constrained_fun =
  >   [%melange_only (fun x -> Js.log (constrained_helper x) : int -> unit)]
  > 
  > (* Default parameter expression referencing an in-scope value *)
  > let default_base = "https://example.com"
  > let%melange_only use_default_param ?abort ?(base = default_base) () =
  >   Js.log (abort, base)
  > 
  > (* Default parameter referencing outer x that is shadowed by parameter ?x *)
  > let x = 42
  > let%melange_only use_shadowed_default ?(x = x) () =
  >   Js.log x
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
  > (* Inline include struct / include [@native_only] struct / open struct / inline constrained include *)
  > include struct
  >   let from_inline_include = 1
  > end
  > 
  > include struct
  >   let from_native_only_include = 2
  > end [@@native_only]
  > 
  > include struct
  >   let from_melange_only_include = Js.null
  > end [@@melange_only]
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
  >   Js.log
  >     ( from_inline_include,
  >       from_native_only_include,
  >       from_melange_only_include,
  >       from_inline_open,
  >       from_inline_sig_include )
  > 
  > (* Local unconstrained structs, nested structs, aliases, local open/include,
  >    inline constrained modules, opaque module aliases, local let module, and first-class module unpacks *)
  > module Local_struct = struct
  >   let member = 10
  >   module Sub = struct
  >     let deep = 20
  >   end
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
  > module Dot_opened = struct
  >   let from_dot_open = 50
  > end
  > 
  > module Constrained_inline : sig
  >   val pub : int
  > end = struct
  >   let pub = 55
  > end
  > 
  > module Ext_alias = List
  > module Type_only_mod = String
  > 
  > let use_local_modules (module Unpacked : Set.S) =
  >   let module Local_in_fn = struct
  >     let local_val = 60
  >   end in
  >   let module Opaque_in_fn = Bytes in
  >   let h =
  >     [%melange_only
  >       fun () ->
  >         let _ : Type_only_mod.t = "" in
  >         Js.log
  >           ( Local_struct.member,
  >             Local_struct.Sub.deep,
  >             Local_alias.member,
  >             from_opened_local,
  >             from_included_local,
  >             Dot_opened.(from_dot_open),
  >             Constrained_inline.pub,
  >             Ext_alias.length [],
  >             Local_in_fn.local_val,
  >             Opaque_in_fn.empty,
  >             Unpacked.empty )]
  >   in
  >   ignore h
  > 
  > (* Sequential local let%melange_only where the second calls the first *)
  > let use_sequential_local_melange_only x =
  >   let%melange_only first () = Js.log x in
  >   let%melange_only second () = first () in
  >   second
  > 
  > (* Object self and instance val *)
  > let use_object () =
  >   object (self)
  >     val state = 1
  >     method run = [%melange_only fun () -> Js.log (self, state)]
  >   end
  > 
  > (* Functor parameter with inline signature *)
  > module Use_functor (Arg : sig type t val go : t -> unit end) = struct
  >   let%melange_only run v = Arg.go v
  > end
  > EOF

  $ ./standalone.exe -impl supported_input.ml | ocamlformat - --enable-outside-detected-project --impl > supported.ml
  $ ocamlc -c -w +A -alert @melange_only supported.mli
  $ ocamlc -c -w +A -alert @melange_only -I . supported.ml

Verify selected generated expansions:

  $ grep -A 5 "let use_state_example" supported.ml
  let use_state_example () =
    let a, set_a = use_state 4 in
    use_effect (fun () ->
        let _ = set_a in
        Ppx_platform.fail_melange_only "<unkwnown>");
    a

  $ grep -A 7 "let (use_shadowed_default" supported.ml
  let (use_shadowed_default
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun ?x:_ ->
    let _ = x in
    Ppx_platform.fail_melange_only "use_shadowed_default")

2. Shadowing and genuinely unused bindings STILL warn on native

  $ cat > shadowing.mli << 'EOF'
  > val use_shadowed : unit -> unit [@@alert melange_only]
  > val use_nonrec_rhs : unit -> unit [@@alert melange_only]
  > val use_param_shadow : int -> unit [@@alert melange_only]
  > val use_state_with_unused : unit -> unit
  > EOF

  $ cat > shadowing_input.ml << 'EOF'
  > (* Outer x shadowed by inner let x = 2: outer x is NOT used and still warns W32 *)
  > let shadowed_by_let = 1
  > let%melange_only use_shadowed () =
  >   let shadowed_by_let = 2 in
  >   Js.log shadowed_by_let
  > 
  > (* Non-rec let x = x + 1 uses outer x in its RHS: outer x IS used (no W32) *)
  > let used_in_nonrec_rhs = 1
  > let%melange_only use_nonrec_rhs () =
  >   let used_in_nonrec_rhs = used_in_nonrec_rhs + 1 in
  >   Js.log used_in_nonrec_rhs
  > 
  > (* Parameter shadows outer binding: outer binding is NOT used and still warns W32 *)
  > let shadowed_by_param = 1
  > let%melange_only use_param_shadow shadowed_by_param =
  >   Js.log shadowed_by_param
  > 
  > (* Unused sibling binding in useState still warns W26 while set_a does not *)
  > let use_state init = (init, fun _ -> ())
  > let use_effect (f : unit -> unit option) = ignore f
  > let use_state_with_unused () =
  >   let unused_a, set_a = use_state 4 in
  >   use_effect [%melange_only fun () -> set_a 33; None]
  > EOF

  $ ./standalone.exe -impl shadowing_input.ml | ocamlformat - --enable-outside-detected-project --impl > shadowing.ml
  $ ocamlc -c -w +A shadowing.mli
  $ ocamlc -c -w +A -I . shadowing.ml
  File "shadowing.ml", line 1, characters 4-19:
  1 | let shadowed_by_let = 1
          ^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value shadowed_by_let.
  
  File "shadowing.ml", line 26, characters 4-21:
  26 | let shadowed_by_param = 1
           ^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value shadowed_by_param.
  
  File "shadowing.ml", line 43, characters 6-14:
  43 |   let unused_a, set_a = use_state 4 in
             ^^^^^^^^
  Warning 27 [unused-var-strict]: unused variable unused_a.
