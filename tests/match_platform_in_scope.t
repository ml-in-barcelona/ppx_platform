Detecting in-scope identifiers in the discarded branch of match%platform on both Native and Js.

  $ cat > ppx_platform.ml << 'EOF'
  > exception Melange_only of string
  > let fail_melange_only name = raise (Melange_only name)
  > EOF
  $ ocamlc -c ppx_platform.ml

1. Compiles with zero warnings and zero @melange_only alerts on BOTH Native and Js (-js) under -warn-error +A

  $ cat > both.mli << 'EOF'
  > val param_melange_only : int -> int
  > val param_native_only : int -> int
  > val param_both_branches : int -> int
  > val local_let_discarded : unit -> int
  > val local_melange_only_called_in_match : int -> int option
  > val top_melange_only_called_in_match : int -> int
  > val rec_only_in_melange : int -> int
  > val rec_only_in_native : int -> int
  > val dropped_items_not_referenced : unit -> int
  > val kept_branch_preprocessed : int -> int
  > val poly_preserved : int list * string list
  > val nested_match_platform : int -> int -> int -> int
  > EOF

  $ cat > both_input.ml << 'EOF'
  > (* Parameter only used in Melange branch *)
  > let param_melange_only x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> x + 1
  > 
  > (* Parameter only used in Native branch *)
  > let param_native_only x =
  >   match%platform () with
  >   | Native -> x + 1
  >   | Melange -> 0
  > 
  > (* Parameter used in both branches: no redundant let _ = emitted *)
  > let param_both_branches x =
  >   match%platform () with
  >   | Native -> x + 1
  >   | Melange -> x + 2
  > 
  > (* Local let bindings only used in discarded branch *)
  > let local_let_discarded () =
  >   let native_val = 1 in
  >   let melange_val = 2 in
  >   match%platform () with
  >   | Native -> native_val
  >   | Melange -> melange_val
  > 
  > (* Local let%melange_only called only in Melange branch (Pricing2022 pattern) *)
  > let local_melange_only_called_in_match x =
  >   let%melange_only get () = Some x in
  >   match%platform () with
  >   | Native -> None
  >   | Melange -> get ()
  > 
  > (* Top-level let%melange_only called only in Melange branch (no @melange_only alert on Native) *)
  > let%melange_only top_mel_helper x = x + 1
  > 
  > let top_melange_only_called_in_match x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> top_mel_helper x
  > 
  > (* let rec that only recurses in one branch (avoids W39 unused-rec-flag) *)
  > let rec rec_only_in_melange x =
  >   match%platform () with
  >   | Native -> x
  >   | Melange -> if x > 0 then rec_only_in_melange (x - 1) else 0
  > 
  > let rec rec_only_in_native x =
  >   match%platform () with
  >   | Native -> if x > 0 then rec_only_in_native (x - 1) else 0
  >   | Melange -> x
  > 
  > (* Items dropped by [@@melange_only] / [@@native_only] are not emitted as let _ = *)
  > let only_on_melange = 10 [@@melange_only]
  > let only_on_native = 20 [@@native_only]
  > 
  > let dropped_items_not_referenced () =
  >   match%platform () with
  >   | Native -> only_on_native
  >   | Melange -> only_on_melange
  > 
  > (* Preprocess runs on the kept branch and skips the discarded branch *)
  > module Nat_open = struct
  >   let v = 1
  > end [@@native_only]
  > module Mel_open = struct
  >   let v = 2
  > end [@@melange_only]
  > 
  > let kept_branch_preprocessed x =
  >   match%platform () with
  >   | Native ->
  >       let open [@native_only] Nat_open in
  >       x + v
  >   | Melange ->
  >       let open [@melange_only] Mel_open in
  >       x + v
  > 
  > (* Value restriction: polymorphic value stays polymorphic when wrapped in let _ = *)
  > let poly_empty =
  >   let poly_helper = 1 in
  >   match%platform () with
  >   | Native -> []
  >   | Melange -> if poly_helper > 0 then [] else []
  > let poly_preserved = (poly_empty, poly_empty)
  > 
  > (* Nested match%platform *)
  > let nested_match_platform a b c =
  >   match%platform () with
  >   | Native -> a
  >   | Melange -> (
  >       match%platform () with
  >       | Native -> b
  >       | Melange -> c)
  > EOF

  $ ./standalone.exe -impl both_input.ml | ocamlformat - --enable-outside-detected-project --impl > both_native.ml
  $ ./standalone.exe -impl both_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > both_js.ml

  $ cp both.mli both_native.mli
  $ cp both.mli both_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only both_native.mli
  $ ocamlc -c -w +A -warn-error +A -alert @melange_only -I . both_native.ml
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only both_js.mli
  $ ocamlc -c -w +A -warn-error +A -alert -melange_only -I . both_js.ml

Verify selected generated expansions:

  $ grep -A 0 "let param_both_branches" both_native.ml
  let param_both_branches x = x + 1

  $ grep -A 2 "let rec rec_only_in_melange" both_native.ml
  let rec rec_only_in_melange x =
    let _ = rec_only_in_melange in
    x

  $ grep -A 2 "let top_melange_only_called_in_match" both_native.ml
  let top_melange_only_called_in_match x =
    let _ = x in
    0

2. Shadowing, genuinely unused bindings, and kept-branch @melange_only alerts STILL fire

  $ cat > warnings.mli << 'EOF'
  > val unused_and_shadowed : int -> int -> int
  > val alert_in_native_branch : int -> int
  > EOF

  $ cat > warnings_input.ml << 'EOF'
  > let shadowed_outer = 1
  > 
  > let unused_and_shadowed used_in_melange genuinely_unused =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange ->
  >       let shadowed_outer = 2 in
  >       used_in_melange + shadowed_outer
  > 
  > let%melange_only mel_only_fn x = x + 1
  > 
  > let alert_in_native_branch x =
  >   match%platform () with
  >   | Native -> mel_only_fn x
  >   | Melange -> mel_only_fn x
  > EOF

  $ ./standalone.exe -impl warnings_input.ml | ocamlformat - --enable-outside-detected-project --impl > warnings.ml
  $ ocamlc -c -w +A -alert @melange_only warnings.mli
  $ ocamlc -c -w +A -alert @melange_only -I . warnings.ml
  File "warnings.ml", line 18, characters 31-42:
  18 | let alert_in_native_branch x = mel_only_fn x
                                      ^^^^^^^^^^^
  Error (alert melange_only): mel_only_fn
  This value only exists in the Melange build. Use it inside a let%melange_only function, or a Melange branch of match%platform.
  
  File "warnings.ml", line 1, characters 4-18:
  1 | let shadowed_outer = 1
          ^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value shadowed_outer.
  
  File "warnings.ml", line 3, characters 40-56:
  3 | let unused_and_shadowed used_in_melange genuinely_unused =
                                              ^^^^^^^^^^^^^^^^
  Warning 27 [unused-var-strict]: unused variable genuinely_unused.
  [2]

3. Module paths get no ignore: the output compiles on both targets, and members
used only in the discarded branch still warn

  $ cat > modules.mli << 'EOF'
  > val sig_melange_only_called_in_match : int -> int
  > val local_modules : unit -> int
  > EOF

  $ cat > modules_input.ml << 'EOF'
  > (* Inline-sig module with [@@alert melange_only] called only in Melange branch *)
  > module Sig_mod : sig
  >   val f : int -> int [@@alert melange_only]
  > end = struct
  >   let%melange_only f x = x + 1
  > end
  > 
  > let sig_melange_only_called_in_match x =
  >   match%platform () with
  >   | Native -> 0
  >   | Melange -> Sig_mod.f x
  > 
  > (* Local struct and opaque module alias used only in discarded branch *)
  > module Local_struct = struct
  >   let nat = 1
  >   let mel = 2
  > end
  > module List_alias = List
  > 
  > let local_modules () =
  >   match%platform () with
  >   | Native -> Local_struct.nat
  >   | Melange -> Local_struct.mel + List_alias.length []
  > EOF

  $ ./standalone.exe -impl modules_input.ml | ocamlformat - --enable-outside-detected-project --impl > modules_native.ml
  $ ./standalone.exe -impl modules_input.ml -js | ocamlformat - --enable-outside-detected-project --impl > modules_js.ml
  $ grep -n "let _ = \|let module _" modules_native.ml modules_js.ml
  modules_native.ml:11:    let _ = x in
  modules_native.ml:18:  let _ = x in
  $ cp modules.mli modules_native.mli
  $ cp modules.mli modules_js.mli
  $ ocamlc -c -w +A -alert @melange_only modules_native.mli
  $ ocamlc -c -w +A -alert @melange_only -I . modules_native.ml
  File "modules_native.ml", line 2, characters 2-43:
  2 |   val f : int -> int [@@alert melange_only]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 32 [unused-value-declaration]: unused value f.
  
  File "modules_native.ml", lines 1-15, characters 0-3:
   1 | module Sig_mod : sig
   2 |   val f : int -> int [@@alert melange_only]
   3 | end = struct
   4 |   let (f
   5 |        [@alert
  ...
  12 |     Ppx_platform.fail_melange_only "f")
  13 |     [@alert "-melange_only"]
  14 |   [@@warning "-32"]
  15 | end
  Warning 60 [unused-module]: unused module Sig_mod.
  
  File "modules_native.ml", line 23, characters 6-9:
  23 |   let mel = 2
             ^^^
  Warning 32 [unused-value-declaration]: unused value mel.
  
  File "modules_native.ml", line 26, characters 0-24:
  26 | module List_alias = List
       ^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 60 [unused-module]: unused module List_alias.
  $ ocamlc -c -w +A -alert -melange_only modules_js.mli
  $ ocamlc -c -w +A -alert -melange_only -I . modules_js.ml
  File "modules_js.ml", line 10, characters 6-9:
  10 |   let nat = 1
             ^^^
  Warning 32 [unused-value-declaration]: unused value nat.
