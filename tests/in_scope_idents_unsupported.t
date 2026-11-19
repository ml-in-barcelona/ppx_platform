Cases that a purely syntactic PPX cannot resolve without .cmi / typing information.
All cases below compile safely on native (never producing Unbound value/module),
while documenting the exact unused warnings that remain.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

External shared helper module (compiled separately, so ppx_platform has no .cmi access):

  $ cat > ext_helpers.mli << 'EOF'
  > module type S = sig
  >   val from_named_sig : unit -> unit
  > end
  > val from_ext_open : unit -> unit
  > val from_ext_local_open : unit -> unit
  > val from_ext_alias_open : unit -> unit
  > val from_ext_include : unit -> unit
  > module Make : functor (X : sig end) -> sig
  >   val from_functor_include : unit -> unit
  > end
  > EOF
  $ cat > ext_helpers.ml << 'EOF'
  > module type S = sig
  >   val from_named_sig : unit -> unit
  > end
  > let from_ext_open () = ()
  > let from_ext_local_open () = ()
  > let from_ext_alias_open () = ()
  > let from_ext_include () = ()
  > module Make (X : sig end) = struct
  >   let from_functor_include () = ()
  > end
  > EOF
  $ ocamlc -c ext_helpers.mli
  $ ocamlc -c ext_helpers.ml

  $ cat > unsupported.mli << 'EOF'
  > val use_ext_open : unit -> unit [@@alert melange_only]
  > val use_local_open : unit -> unit
  > val use_opaque_alias_open : unit -> unit [@@alert melange_only]
  > val use_named_sig_open : unit -> unit [@@alert melange_only]
  > val use_ext_include : unit -> unit [@@alert melange_only]
  > val use_named_sig_include : unit -> unit [@@alert melange_only]
  > val use_functor_include : unit -> unit [@@alert melange_only]
  > val use_named_sig_module : unit -> unit [@@alert melange_only]
  > val use_non_values : unit -> unit [@@alert melange_only]
  > EOF

  $ cat > unsupported_input.ml << 'EOF'
  > (* 1. Top-level open of an external module -> Warning 33 (unused open) *)
  > open Ext_helpers
  > 
  > let%melange_only use_ext_open () = from_ext_open ()
  > 
  > (* 2. Local let open of an external module -> Warning 33 (unused open) *)
  > let use_local_open () =
  >   let open Ext_helpers in
  >   let f = [%melange_only fun () -> from_ext_local_open ()] in
  >   ignore f
  > 
  > (* 3. open of a local alias to an external module (opaque) -> Warning 33 (unused open) *)
  > module Ext_alias = Ext_helpers
  > open Ext_alias
  > 
  > let%melange_only use_opaque_alias_open () = from_ext_alias_open ()
  > 
  > (* 4. open of a local module constrained by a named external signature (opaque) -> Warning 33 *)
  > module Named_sig_opened : Ext_helpers.S = struct
  >   let from_named_sig () = ()
  > end
  > open Named_sig_opened
  > 
  > let%melange_only use_named_sig_open () = from_named_sig ()
  > 
  > (* 5. include of an external module -> PPX cannot know its exports; compiles safely without emitting let _ = *)
  > include Ext_helpers
  > 
  > let%melange_only use_ext_include () = from_ext_include ()
  > 
  > (* 6. include of a struct constrained by a named external signature -> opaque so hidden members never cause Unbound value *)
  > include (
  >   struct
  >     let secret_hidden = 1
  >     let from_named_sig () = ()
  >   end : Ext_helpers.S)
  > 
  > let%melange_only use_named_sig_include () =
  >   from_named_sig ();
  >   Js.log secret_hidden
  > 
  > (* 7. include of a functor application -> opaque *)
  > include Ext_helpers.Make (struct end)
  > 
  > let%melange_only use_functor_include () = from_functor_include ()
  > 
  > (* 8. Local module constrained by a named external signature: let module _ = M silences W60 on M,
  >    while hidden internal values inside M still warn W32 *)
  > module Named_sig_mod : Ext_helpers.S = struct
  >   let from_named_sig () = ()
  >   let priv = 2
  > end
  > 
  > let%melange_only use_named_sig_module () = Named_sig_mod.from_named_sig ()
  > 
  > (* 9. Non-value declarations: types (W34), constructors (W37), exceptions (W38), record fields (W69) *)
  > type client_type = int
  > type action = Shared | Client_only
  > type state = { shared : int; client_only : string }
  > exception Client_exn
  > 
  > let _ = (Shared, { shared = 1; client_only = "" }.shared)
  > 
  > let%melange_only use_non_values () =
  >   let (_ : client_type) = 1 in
  >   let s = { shared = 1; client_only = "hi" } in
  >   if false then raise Client_exn;
  >   Js.log (Client_only, s.client_only)
  > EOF

  $ ./standalone.exe -impl unsupported_input.ml | ocamlformat - --enable-outside-detected-project --impl > unsupported.ml
  $ ocamlc -c -w +A unsupported.mli
  $ ocamlc -c -w +A -I . unsupported.ml
  File "unsupported.ml", line 1, characters 0-16:
  1 | open Ext_helpers
      ^^^^^^^^^^^^^^^^
  Warning 33 [unused-open]: unused open Ext_helpers.
  
  File "unsupported.ml", line 14, characters 6-22:
  14 |   let open Ext_helpers in
             ^^^^^^^^^^^^^^^^
  Warning 33 [unused-open]: unused open Ext_helpers.
  
  File "unsupported.ml", line 19, characters 0-14:
  19 | open Ext_alias
       ^^^^^^^^^^^^^^
  Warning 33 [unused-open]: unused open Ext_alias.
  
  File "unsupported.ml", line 35, characters 0-21:
  35 | open Named_sig_opened
       ^^^^^^^^^^^^^^^^^^^^^
  Warning 33 [unused-open]: unused open Named_sig_opened.
  
  File "unsupported.ml", line 61, characters 8-21:
  61 |     let secret_hidden = 1
               ^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value secret_hidden.
  
  File "unsupported.ml", line 90, characters 6-10:
  90 |   let priv = 2
             ^^^^
  Warning 32 [unused-value-declaration]: unused value priv.
  
  File "unsupported.ml", line 104, characters 0-22:
  104 | type client_type = int
        ^^^^^^^^^^^^^^^^^^^^^^
  Warning 34 [unused-type-declaration]: unused type client_type.
  
  File "unsupported.ml", line 105, characters 21-34:
  105 | type action = Shared | Client_only
                             ^^^^^^^^^^^^^
  Warning 37 [unused-constructor]: unused constructor Client_only.
  
  File "unsupported.ml", line 106, characters 29-49:
  106 | type state = { shared : int; client_only : string }
                                     ^^^^^^^^^^^^^^^^^^^^
  Warning 69 [unused-field]: record field client_only is never read.
    (However, this field is used to build or mutate values.)
  
  File "unsupported.ml", line 108, characters 0-20:
  108 | exception Client_exn
        ^^^^^^^^^^^^^^^^^^^^
  Warning 38 [unused-extension]: unused exception Client_exn

Confirm that opaque include/open cases did NOT emit unbound identifiers:

  $ grep -A 8 "let (use_ext_include" unsupported.ml
  let (use_ext_include
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun () ->
    Ppx_platform.fail_melange_only "use_ext_include")
    [@alert "-melange_only"]
  [@@warning "-32"]

  $ grep -A 8 "let (use_named_sig_include" unsupported.ml
  let (use_named_sig_include
       [@alert
         melange_only
           "This value only exists in the Melange build. Use it inside a \
            let%melange_only function, or a Melange branch of match%platform."]) =
   (fun () ->
    Ppx_platform.fail_melange_only "use_named_sig_include")
    [@alert "-melange_only"]
  [@@warning "-32"]
